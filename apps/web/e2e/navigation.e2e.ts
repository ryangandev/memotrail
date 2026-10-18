import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test, type Locator } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

type SidebarMotionFrame = {
  logoCenter: number;
  navigationCenter: number;
  sidebarWidth: number;
};

async function toggleSidebarAndMeasureMotion(toggle: Locator) {
  const collapsing =
    (await toggle.getAttribute("aria-label")) === "Collapse sidebar";
  await toggle.evaluate((button) => {
    const motionWindow = window as typeof window & {
      sidebarMotionFrames?: Promise<SidebarMotionFrame[]>;
    };
    motionWindow.sidebarMotionFrames = new Promise((resolve) => {
      button.addEventListener(
        "click",
        () => {
          const sidebar = document.querySelector("aside")!;
          const logo = sidebar.querySelector(
            'a[aria-label="MemoTrail dashboard"] svg',
          )!;
          const navigationIcon = sidebar.querySelector(
            'nav[aria-label="Primary navigation"] a svg',
          )!;
          const frames: SidebarMotionFrame[] = [];
          const started = performance.now();
          const sample = () => {
            const logoBox = logo.getBoundingClientRect();
            const navigationBox = navigationIcon.getBoundingClientRect();
            frames.push({
              logoCenter: logoBox.x + logoBox.width / 2,
              navigationCenter: navigationBox.x + navigationBox.width / 2,
              sidebarWidth: sidebar.getBoundingClientRect().width,
            });
            if (performance.now() - started < 320) {
              requestAnimationFrame(sample);
            } else {
              resolve(frames);
            }
          };
          sample();
        },
        { once: true, capture: true },
      );
    });
  });
  await toggle.click();
  const frames = await toggle.page().evaluate(() => {
    const motionWindow = window as typeof window & {
      sidebarMotionFrames?: Promise<SidebarMotionFrame[]>;
    };
    return motionWindow.sidebarMotionFrames!;
  });
  const first = frames[0];
  const last = frames.at(-1)!;
  expect(
    frames.some(
      (frame) =>
        frame.sidebarWidth > Math.min(first.sidebarWidth, last.sidebarWidth) &&
        frame.sidebarWidth < Math.max(first.sidebarWidth, last.sidebarWidth),
    ),
    "the measurement includes frames during the width transition",
  ).toBe(true);
  for (const key of ["logoCenter", "navigationCenter"] as const) {
    const lowerBound = Math.min(first[key], last[key]) - 1;
    const upperBound = Math.max(first[key], last[key]) + 1;
    for (const frame of frames) {
      expect(
        frame[key],
        `${key} stays between its resting positions`,
      ).toBeGreaterThanOrEqual(lowerBound);
      expect(
        frame[key],
        `${key} stays between its resting positions`,
      ).toBeLessThanOrEqual(upperBound);
    }
  }
  const brand = toggle.page().locator("aside").getByRole("link", {
    name: "MemoTrail dashboard",
  });
  for (const part of ["outer-ring", "accent", "inner-ring"]) {
    await expect(brand.locator(`[data-brand-part="${part}"]`)).toHaveCSS(
      "transform",
      collapsing
        ? part === "inner-ring"
          ? "matrix(0, -1, 1, 0, 0, 0)"
          : "matrix(0, 1, -1, 0, 0, 0)"
        : "none",
    );
  }
}

test("primary navigation keeps the app shell visible while fresh data loads", async ({
  context,
  page,
}) => {
  const env = JSON.parse(
    execFileSync("supabase", ["status", "-o", "json"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }),
  );
  const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
  const email = `navigation-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  expect(created.error).toBeNull();
  const owner = created.data.user!.id;
  let releaseMapNavigation = () => {};
  const mapNavigationGate = new Promise<void>((resolve) => {
    releaseMapNavigation = resolve;
  });

  try {
    const cookies: { name: string; value: string }[] = [];
    const client = createServerClient(env.API_URL, env.ANON_KEY, {
      cookies: {
        getAll: () => cookies,
        setAll: (values) => {
          cookies.push(...values.map(({ name, value }) => ({ name, value })));
        },
      },
    });
    const link = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    expect(
      (
        await client.auth.verifyOtp({
          type: "magiclink",
          token_hash: link.data.properties!.hashed_token,
        })
      ).error,
    ).toBeNull();
    await context.addCookies(
      cookies.map((cookie) => ({
        ...cookie,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax" as const,
      })),
    );

    let mapNavigationStarted = false;

    await page.route("**/map*", async (route) => {
      const headers = route.request().headers();
      const isRscRequest =
        headers.rsc === "1" ||
        new URL(route.request().url()).searchParams.has("_rsc");

      if (isRscRequest && !mapNavigationStarted) {
        await route.fulfill({
          body: "Map prefetch intentionally unavailable during this test.",
          contentType: "text/plain",
          status: 503,
        });
        return;
      }

      if (isRscRequest) {
        await mapNavigationGate;
      }

      await route.continue();
    });
    await page.goto("/");

    const homeCapture = page.getByRole("form", {
      name: "Quick capture",
      exact: true,
    });
    const homeCaptureHeading = homeCapture.getByRole("heading", {
      name: "What’s on your mind?",
      exact: true,
    });
    const homeEntryText = homeCapture.getByRole("textbox", {
      name: "Entry text",
      exact: true,
    });
    await expect(homeCaptureHeading).toBeVisible();
    await expect(homeEntryText).toBeVisible();
    await expect(
      homeCapture.locator('[data-rich-text-editor="true"]'),
    ).toHaveAttribute("data-variant", "embedded");
    const homeCaptureLeft = await homeCapture.evaluate(
      (element) => element.getBoundingClientRect().left,
    );
    const homeEntryTextLeft = await homeEntryText.evaluate(
      (element) => element.getBoundingClientRect().left,
    );
    expect(Math.round(homeEntryTextLeft - homeCaptureLeft)).toBe(25);
    const homeFormatting = homeCapture.getByRole("toolbar", {
      name: "Text formatting",
      exact: true,
    });
    const homeBoldIconLeft = await homeFormatting
      .getByRole("button", { name: "Bold", exact: true })
      .locator("svg")
      .evaluate((element) => element.getBoundingClientRect().left);
    expect(Math.round(homeBoldIconLeft)).toBe(Math.round(homeEntryTextLeft));
    const homeToolbarBottom = await homeFormatting.evaluate(
      (element) => element.getBoundingClientRect().bottom,
    );
    const homeActionsTop = await homeCapture
      .locator("[data-capture-actions]")
      .evaluate((element) => element.getBoundingClientRect().top);
    expect(Math.round(homeActionsTop - homeToolbarBottom)).toBe(20);

    const shell = page.getByRole("complementary").filter({
      has: page.getByRole("navigation", { name: "Primary navigation" }),
    });
    await expect(shell).toBeVisible();
    const keyboardBrand = shell.getByRole("link", {
      name: "MemoTrail dashboard",
    });
    await page.keyboard.press("Tab");
    await expect(keyboardBrand).toBeFocused();
    await page.screenshot({
      clip: { x: 0, y: 0, width: 240, height: 110 },
      path: test.info().outputPath("memotrail-brand-focus.png"),
    });
    await expect(keyboardBrand).toHaveCSS("outline-style", "none");
    await expect(keyboardBrand).toHaveCSS("box-shadow", /inset/);
    const primaryNavigation = shell.getByRole("navigation", {
      name: "Primary navigation",
    });
    await expect(
      primaryNavigation.getByRole("link", { name: "Library", exact: true }),
    ).toBeVisible();
    const goBack = page.getByRole("button", { name: "Go back" });
    const goForward = page.getByRole("button", { name: "Go forward" });
    await expect(goBack).toBeDisabled();
    await expect(goForward).toBeDisabled();
    await primaryNavigation
      .getByRole("link", { name: "Library", exact: true })
      .click();
    await expect(page).toHaveURL(/\/library$/);
    await expect(goBack).toBeEnabled();
    await expect(goForward).toBeDisabled();
    await goBack.hover();
    await expect(goBack).toHaveCSS(
      "transition-property",
      "color, background-color",
    );
    await expect(goBack.locator("svg")).toHaveCSS("transform", "none");
    await goBack.focus();
    await page.keyboard.press("Tab");
    const panelControl = page.getByRole("button", { name: "Collapse sidebar" });
    await expect(panelControl).toBeFocused();
    await expect(panelControl).toHaveCSS("border-radius", "8px");
    const panelFocusShadow = await panelControl.evaluate(
      (element) => getComputedStyle(element).boxShadow,
    );
    await page.keyboard.press("Shift+Tab");
    await expect(goBack).toBeFocused();
    await expect(goBack).toHaveCSS("outline-style", "none");
    await expect(goBack).toHaveCSS("box-shadow", panelFocusShadow);
    await goBack.screenshot({
      path: test.info().outputPath("memotrail-history-focus.png"),
    });
    await goBack.click();
    await expect(page).toHaveURL(/\/$/);
    await expect(goForward).toBeEnabled();
    await goBack.focus();
    await page.keyboard.press("Tab");
    await expect(goForward).toBeFocused();
    await expect(goForward).toHaveCSS("outline-style", "none");
    await expect(goForward).toHaveCSS("box-shadow", panelFocusShadow);
    await goForward.click();
    await expect(page).toHaveURL(/\/library$/);
    await primaryNavigation
      .getByRole("link", { name: "Dashboard", exact: true })
      .click();
    await expect(page).toHaveURL(/\/$/);
    await expect(goForward).toBeDisabled();
    await expect(
      primaryNavigation.getByRole("link", { name: "Inbox", exact: true }),
    ).toHaveCount(0);
    await expect(
      shell.getByText("Focused views", { exact: true }),
    ).toBeVisible();
    await expect(shell.getByText("Organize", { exact: true })).toBeVisible();
    await expect(shell.getByRole("button", { name: "New entry" })).toHaveCount(
      0,
    );
    await expect(page.getByText("Saved", { exact: true })).toHaveCount(0);
    const searchShortcut = page.getByRole("button", {
      name: "Search your trail",
      exact: true,
    });
    const newEntryShortcut = page.getByRole("button", {
      name: "New entry",
      exact: true,
    });
    await expect(searchShortcut).toContainText("⌘ K");
    await expect(searchShortcut).not.toContainText("Search your trail");
    await expect(newEntryShortcut).toContainText("⌘ J");
    await expect(newEntryShortcut).toContainText("What’s on your mind?");
    // Captures land in Library, so the top bar keeps no Inbox control.
    await expect(page.getByRole("link", { name: /Inbox/ })).toHaveCount(0);
    const [dockBox, searchBox] = await Promise.all([
      newEntryShortcut.boundingBox(),
      searchShortcut.boundingBox(),
    ]);
    expect(dockBox!.x + dockBox!.width).toBeLessThan(searchBox!.x);
    expect(dockBox!.y).toBeCloseTo(searchBox!.y, 0);
    await expect(
      page
        .locator("main > header")
        .getByRole("button", { name: "New entry", exact: true }),
    ).toHaveCount(0);
    await expect(
      page
        .locator("main > header")
        .getByRole("button", { name: "Search your trail", exact: true }),
    ).toHaveCount(0);
    await expect(newEntryShortcut).toHaveCSS("backdrop-filter", /blur/);
    await expect(shell.getByText(email, { exact: true })).toHaveCount(0);
    await expect(
      shell
        .getByRole("navigation", { name: "Settings navigation" })
        .getByRole("link", { name: "Settings", exact: true }),
    ).toHaveCount(1);
    await expect(
      shell.getByRole("note", { name: "Private cloud sync" }),
    ).toHaveCount(0);
    await page.reload();
    await expect(
      shell.getByRole("note", { name: "Private cloud sync" }),
    ).toHaveCount(0);
    const sidebarDividers = shell.getByRole("separator");
    await expect(sidebarDividers).toHaveCount(3);
    const dividerMargins = await sidebarDividers.evaluateAll((elements) =>
      elements.map((element) => {
        const style = getComputedStyle(element);
        return [style.marginTop, style.marginBottom];
      }),
    );
    expect(dividerMargins.at(-1)).toEqual(dividerMargins[0]);
    await shell.evaluate((element) => {
      element.setAttribute("data-shell-instance", "kept");
    });

    await page.setViewportSize({ width: 1280, height: 560 });
    const scrollRegion = page.getByRole("region", {
      name: "Sidebar navigation",
    });
    const brand = shell.getByRole("link", {
      name: "MemoTrail dashboard",
      exact: true,
    });
    const homeLink = shell
      .getByRole("navigation", { name: "Primary navigation" })
      .getByRole("link", { name: "Dashboard", exact: true });
    const capture = newEntryShortcut;
    const brandBottom = await brand.evaluate(
      (element) => element.getBoundingClientRect().bottom,
    );
    const homeTop = await homeLink.evaluate(
      (element) => element.getBoundingClientRect().top,
    );
    expect(Math.round(homeTop - brandBottom)).toBe(20);
    const scrollRegionRight = await scrollRegion.evaluate(
      (element) => element.getBoundingClientRect().right,
    );
    const homeRight = await homeLink.evaluate(
      (element) => element.getBoundingClientRect().right,
    );
    expect(Math.round(scrollRegionRight - homeRight)).toBe(8);
    const brandMarkLeft = await brand
      .locator("svg")
      .evaluate((element) => element.getBoundingClientRect().left);
    const homeIconLeft = await homeLink
      .locator("svg")
      .evaluate((element) => element.getBoundingClientRect().left);
    expect(Math.round(homeIconLeft - brandMarkLeft)).toBe(4);
    const brandTop = await brand.evaluate(
      (element) => element.getBoundingClientRect().top,
    );
    const captureTop = await capture.evaluate(
      (element) => element.getBoundingClientRect().top,
    );
    await scrollRegion.evaluate((element) => {
      element.scrollTop = element.scrollHeight;
    });
    await expect(
      page
        .getByRole("navigation", { name: "Settings navigation" })
        .getByRole("link", { name: "Settings", exact: true }),
    ).toBeVisible();
    await expect(brand).toBeVisible();
    await expect(capture).toBeVisible();
    await page.screenshot({
      caret: "initial",
      path: test.info().outputPath("memotrail-sidebar-scroll.png"),
    });
    expect(
      await brand.evaluate((element) => element.getBoundingClientRect().top),
    ).toBe(brandTop);
    expect(
      await capture.evaluate((element) => element.getBoundingClientRect().top),
    ).toBe(captureTop);
    await page.setViewportSize({ width: 1280, height: 720 });
    await scrollRegion.evaluate((element) => {
      element.scrollTop = 0;
    });

    expect(
      await shell.evaluate((element) =>
        getComputedStyle(element)
          .transitionDuration.split(", ")
          .some((duration) => Number.parseFloat(duration) > 0),
      ),
    ).toBe(true);
    for (let repetition = 0; repetition < 2; repetition++) {
      await toggleSidebarAndMeasureMotion(
        page.getByRole("button", { name: "Collapse sidebar" }),
      );
      await toggleSidebarAndMeasureMotion(
        page.getByRole("button", { name: "Expand sidebar" }),
      );
    }
    await toggleSidebarAndMeasureMotion(
      page.getByRole("button", { name: "Collapse sidebar" }),
    );
    await expect(page.locator('[data-sidebar-collapsed="true"]')).toBeVisible();
    await expect(shell).toHaveCSS("width", "64px");
    await expect(page.locator("main")).toHaveCSS("margin-left", "64px");
    await expect(homeLink).toBeInViewport();
    const [collapsedRailBox, activeHomeBox] = await Promise.all([
      shell.boundingBox(),
      homeLink.boundingBox(),
    ]);
    expect(
      (collapsedRailBox?.x ?? 0) +
        (collapsedRailBox?.width ?? 0) -
        ((activeHomeBox?.x ?? 0) + (activeHomeBox?.width ?? 0)),
    ).toBeGreaterThanOrEqual(7);
    await expect(homeCaptureHeading).toBeVisible();
    const collapsedBrand = shell.getByRole("link", {
      name: "MemoTrail dashboard",
    });
    await expect(collapsedBrand).toBeVisible();
    await homeLink.focus();
    await page.keyboard.press("Shift+Tab");
    await expect(collapsedBrand).toBeFocused();
    await expect(collapsedBrand).toHaveCSS("outline-style", "none");
    await expect(collapsedBrand).toHaveCSS("box-shadow", /inset/);
    await expect(
      collapsedBrand.getByText("MemoTrail", { exact: true }),
    ).toBeHidden();
    const logoBox = await collapsedBrand.locator("svg").boundingBox();
    expect(logoBox?.width).toBe(29);
    expect(logoBox?.height).toBe(29);
    await expect(homeLink.locator("svg")).toHaveCSS("width", "18px");
    await expect(homeLink.locator("svg")).toHaveCSS("height", "18px");
    expect(
      Math.abs(
        (logoBox?.x ?? 0) +
          (logoBox?.width ?? 0) / 2 -
          ((activeHomeBox?.x ?? 0) + (activeHomeBox?.width ?? 0) / 2),
      ),
    ).toBeLessThanOrEqual(1);
    const expandSidebar = page.getByRole("button", {
      name: "Expand sidebar",
    });
    await expect(expandSidebar.locator("svg circle")).toHaveCount(3);
    await expect(expandSidebar.locator("svg")).toHaveAttribute("width", "18");
    await expect(expandSidebar.locator("svg")).toHaveAttribute("height", "18");
    const [forwardBox, toggleBox] = await Promise.all([
      goForward.boundingBox(),
      expandSidebar.boundingBox(),
    ]);
    expect(toggleBox?.width).toBe(36);
    expect(toggleBox?.height).toBe(36);
    expect(toggleBox?.x).toBeGreaterThan(
      (forwardBox?.x ?? 0) + (forwardBox?.width ?? 0),
    );
    await expect(
      shell.getByRole("button", { name: "Expand sidebar" }),
    ).toHaveCount(0);
    const collapsedLibrary = primaryNavigation.getByRole("link", {
      name: "Library",
      exact: true,
    });
    await expect(collapsedLibrary).toBeVisible();
    await expect(homeLink).toHaveCSS("width", "40px");
    await expect(homeLink).toHaveCSS("height", "40px");
    await collapsedLibrary.hover();
    await expect(collapsedLibrary).toHaveCSS("width", "40px");
    await expect(collapsedLibrary).toHaveCSS("height", "40px");
    await page.screenshot({
      animations: "disabled",
      caret: "initial",
      path: test.info().outputPath("memotrail-sidebar-collapsed.png"),
    });
    await page.mouse.move(800, 100);
    // Reach the link by keyboard so it shows its keyboard focus ring.
    await homeLink.focus();
    await page.keyboard.press("Shift+Tab");
    await page.keyboard.press("Tab");
    await expect(homeLink).toBeFocused();
    await expect(homeLink).toHaveCSS("outline-style", "none");
    await expect(homeLink).toHaveCSS("box-shadow", /inset/);
    await page.screenshot({
      animations: "disabled",
      caret: "initial",
      path: test.info().outputPath("memotrail-sidebar-focus-collapsed.png"),
    });
    const previousTheme = await page.locator("html").getAttribute("data-theme");
    await page.evaluate(() =>
      document.documentElement.setAttribute("data-theme", "dark"),
    );
    await page.screenshot({
      animations: "disabled",
      caret: "initial",
      path: test.info().outputPath("memotrail-sidebar-collapsed-dark.png"),
    });
    await page.evaluate((theme) => {
      if (theme) document.documentElement.setAttribute("data-theme", theme);
      else document.documentElement.removeAttribute("data-theme");
    }, previousTheme);
    await collapsedLibrary.click();
    await expect(page).toHaveURL(/\/library$/);
    await page.reload();
    await expect(shell).toHaveCSS("width", "64px");
    await expect(brand.locator('[data-brand-part="outer-ring"]')).toHaveCSS(
      "transform",
      "matrix(0, 1, -1, 0, 0, 0)",
    );
    await primaryNavigation
      .getByRole("link", { name: "Dashboard", exact: true })
      .click();
    await expect(page).toHaveURL(/\/$/);
    await page.setViewportSize({ width: 390, height: 844 });
    await expect(shell).toBeHidden();
    await expect(expandSidebar).toBeHidden();
    await expect(page.locator("main")).toHaveCSS("margin-left", "0px");
    await expect(
      page.getByRole("navigation", { name: "Mobile navigation" }),
    ).toBeVisible();
    for (const label of ["Dashboard", "Timeline", "Library", "Map"]) {
      await expect(
        page
          .getByRole("navigation", { name: "Mobile navigation" })
          .getByText(label),
      ).toHaveCSS("opacity", "1");
    }
    await page.setViewportSize({ width: 320, height: 700 });
    const mobileNavigation = page.getByRole("navigation", {
      name: "Mobile navigation",
    });
    await expect(mobileNavigation.locator(":scope > *")).toHaveCount(5);
    const moreButton = mobileNavigation.getByRole("button", {
      name: "More destinations",
    });
    await moreButton.click();
    const moreDestinations = page.getByRole("navigation", {
      name: "More destinations",
    });
    await expect(moreDestinations).toBeVisible();
    await moreDestinations.getByRole("link", { name: "Tags" }).click();
    await expect(page).toHaveURL(/\/tags$/);
    await expect(
      page.getByRole("heading", { name: "Tags", exact: true }),
    ).toBeVisible();
    await expect(moreDestinations).toBeHidden();
    await page.waitForLoadState("networkidle");
    await moreButton.click();
    await expect(moreDestinations).toBeVisible();
    await expect(
      moreDestinations.getByRole("link", { name: "Tags" }),
    ).toHaveAttribute("aria-current", "page");
    await page.keyboard.press("Escape");
    await expect(moreDestinations).toBeHidden();
    await expect(moreButton).toBeFocused();
    await mobileNavigation.getByRole("link", { name: "Dashboard" }).click();
    await page.setViewportSize({ width: 1280, height: 720 });
    await toggleSidebarAndMeasureMotion(
      page.getByRole("button", { name: "Expand sidebar" }),
    );
    await expect(shell).toHaveCSS("width", "224px");
    await expect(page.locator("main")).toHaveCSS("margin-left", "224px");
    // Reach the link by keyboard so it shows its keyboard focus ring.
    await homeLink.focus();
    await page.keyboard.press("Shift+Tab");
    await page.keyboard.press("Tab");
    await expect(homeLink).toBeFocused();
    await expect(homeLink).toHaveCSS("outline-style", "none");
    await expect(homeLink).toHaveCSS("box-shadow", /inset/);
    await page.emulateMedia({ reducedMotion: "reduce" });
    await expect(shell).toHaveCSS("transition-duration", "0s");
    await page.getByRole("button", { name: "Collapse sidebar" }).click();
    for (const part of await brand.locator("path").all()) {
      await expect(part).toHaveCSS("transition-duration", "0s");
      await expect(part).toHaveCSS("transform", "none");
    }
    await page.getByRole("button", { name: "Expand sidebar" }).click();
    await page.emulateMedia({ reducedMotion: "no-preference" });
    await page.screenshot({
      animations: "disabled",
      caret: "initial",
      path: test.info().outputPath("memotrail-sidebar-expanded.png"),
    });
    await shell.evaluate((element) => {
      element.setAttribute("data-shell-instance", "kept");
    });

    await page.keyboard.press("ControlOrMeta+k");
    const commandPalette = page.getByRole("dialog", {
      name: "Search MemoTrail",
    });
    await expect(commandPalette).toBeVisible();
    expect(
      await commandPalette.evaluate(
        (element) => getComputedStyle(element).animationDuration,
      ),
    ).not.toBe("0s");
    await expect(commandPalette).toHaveCSS("opacity", "1");
    await page.screenshot({
      caret: "initial",
      path: test.info().outputPath("memotrail-command-palette.png"),
    });
    await expect(page).toHaveURL(/\/$/);
    await expect(commandPalette.getByRole("searchbox")).toBeFocused();
    await commandPalette.getByRole("searchbox").fill("settings");
    await expect(
      commandPalette.getByRole("button", { name: /Settings/ }),
    ).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(commandPalette).not.toBeVisible();

    mapNavigationStarted = true;
    await page
      .getByRole("navigation", { name: "Primary navigation" })
      .getByRole("link", { name: "Map", exact: true })
      .click({ noWaitAfter: true });

    await expect(
      page.getByRole("status", { name: "Opening Map" }),
    ).toBeVisible();
    await page.screenshot({
      caret: "initial",
      path: test.info().outputPath("memotrail-navigation-loading.png"),
    });
    await expect(shell).toHaveAttribute("data-shell-instance", "kept");
    releaseMapNavigation();
    await expect(page).toHaveURL(/\/map$/);
    await expect(
      page.getByRole("heading", { name: "Map", exact: true }),
    ).toBeVisible();

    await shell
      .getByRole("navigation", { name: "Settings navigation" })
      .getByRole("link", { name: "Settings", exact: true })
      .click();
    await expect(page).toHaveURL(/\/settings$/);
    await expect(shell).toHaveAttribute("data-shell-instance", "kept");

    await page
      .getByRole("navigation", { name: "Primary navigation" })
      .getByRole("link", { name: "Timeline", exact: true })
      .click();
    await expect(page).toHaveURL(/\/timeline$/);
    const birthDatePrompt = page.getByRole("dialog", {
      name: "When did your story begin?",
    });
    await expect(birthDatePrompt).toBeVisible();
    await birthDatePrompt
      .getByRole("button", { name: "Not now", exact: true })
      .click();
    await page.emulateMedia({ colorScheme: "dark" });
    await page.evaluate(() => {
      const captureWindow = window as typeof window & {
        __quickCaptureHeights?: number[];
        __quickCaptureMutationObserver?: MutationObserver;
        __quickCaptureResizeObserver?: ResizeObserver;
      };
      captureWindow.__quickCaptureHeights = [];
      captureWindow.__quickCaptureMutationObserver = new MutationObserver(
        () => {
          const form = document.querySelector<HTMLElement>(
            'dialog[open] form[aria-label="Quick capture"]',
          );
          if (!form) return;

          captureWindow.__quickCaptureMutationObserver?.disconnect();
          const recordHeight = () =>
            captureWindow.__quickCaptureHeights?.push(form.offsetHeight);
          captureWindow.__quickCaptureResizeObserver = new ResizeObserver(
            recordHeight,
          );
          captureWindow.__quickCaptureResizeObserver.observe(form);
          recordHeight();
        },
      );
      // The composer renders while the dialog is closed, so opening it may
      // change only the dialog's open attribute.
      captureWindow.__quickCaptureMutationObserver.observe(document.body, {
        attributeFilter: ["open"],
        childList: true,
        subtree: true,
      });
    });
    await page.keyboard.press("ControlOrMeta+j");

    const quickCapture = page.getByRole("dialog", {
      name: "What’s on your mind?",
    });
    const quickCaptureForm = quickCapture.getByRole("form", {
      name: "Quick capture",
      exact: true,
    });
    const entryText = quickCapture.getByRole("textbox", {
      name: "Entry text",
      exact: true,
    });
    await expect(quickCapture).toBeVisible();
    expect(
      await quickCapture.evaluate(
        (element) => getComputedStyle(element).animationDuration,
      ),
    ).not.toBe("0s");
    await page.waitForTimeout(250);
    const quickCaptureHeights = await page.evaluate(() => {
      const captureWindow = window as typeof window & {
        __quickCaptureHeights?: number[];
        __quickCaptureMutationObserver?: MutationObserver;
        __quickCaptureResizeObserver?: ResizeObserver;
      };
      captureWindow.__quickCaptureMutationObserver?.disconnect();
      captureWindow.__quickCaptureResizeObserver?.disconnect();
      return captureWindow.__quickCaptureHeights ?? [];
    });
    expect(quickCaptureHeights.length).toBeGreaterThan(0);
    expect(
      Math.max(...quickCaptureHeights) - Math.min(...quickCaptureHeights),
    ).toBeLessThanOrEqual(1);
    const dialogHeader = quickCapture.locator("header");
    await expect(dialogHeader).toHaveCSS("border-bottom-width", "0px");
    await expect(dialogHeader.locator("svg")).toHaveCount(2);
    expect(
      await dialogHeader.evaluate(
        (element) => element.getBoundingClientRect().height,
      ),
    ).toBeGreaterThanOrEqual(62);
    expect(
      await dialogHeader.evaluate(
        (element) => element.getBoundingClientRect().height,
      ),
    ).toBeLessThanOrEqual(68);
    await expect(
      quickCapture.getByRole("heading", {
        name: "What’s on your mind?",
        exact: true,
      }),
    ).toBeVisible();
    await expect(
      quickCapture.getByRole("heading", {
        name: "Quick Capture",
        exact: true,
      }),
    ).toHaveCount(0);
    await expect(quickCaptureForm).toHaveCSS("border-width", "0px");
    await expect(quickCaptureForm).toHaveCSS(
      "background-color",
      "rgba(0, 0, 0, 0)",
    );
    await expect(
      quickCapture.getByRole("textbox", {
        name: "Entry title",
        exact: true,
      }),
    ).toHaveCount(0);
    await expect(entryText).toBeEnabled();
    await expect(entryText).toBeFocused();

    const fileChooserPromise = page.waitForEvent("filechooser");
    await quickCapture
      .getByRole("button", { name: "Add photos", exact: true })
      .click();
    await fileChooserPromise;
    await page.keyboard.press("Escape");
    await expect(quickCapture).toBeVisible();
    await quickCapture.locator('input[type="file"]').dispatchEvent("cancel");
    await expect(quickCapture).toBeVisible();

    await entryText.focus();
    await entryText.press("ControlOrMeta+k");
    const linkEditor = quickCapture.getByRole("group", {
      name: "Link editor",
      exact: true,
    });
    await expect(linkEditor).toBeVisible();
    await expect(
      linkEditor.getByLabel("Link URL", { exact: true }),
    ).toBeFocused();
    await page.keyboard.press("Escape");
    await expect(linkEditor).not.toBeVisible();
    await expect(quickCapture).toBeVisible();

    await quickCapture
      .getByRole("button", { name: "Date", exact: true })
      .click();
    await quickCapture
      .getByRole("button", { name: "Choose date", exact: true })
      .click();
    const captureCalendar = page.locator(
      '[data-scope="date-picker"][data-part="content"][data-state="open"]',
    );
    await expect(captureCalendar).toBeVisible();
    expect(
      await captureCalendar.evaluate((element) =>
        Boolean(element.closest("dialog[open]")),
      ),
    ).toBe(true);
    await page.keyboard.press("Escape");
    await expect(captureCalendar).not.toBeVisible();
    await expect(quickCapture).toBeVisible();
    await quickCapture
      .getByRole("button", { name: "Date", exact: true })
      .click();

    await page.keyboard.press("Escape");
    await expect(quickCapture).not.toBeVisible();
    await page.keyboard.press("ControlOrMeta+j");
    await expect(quickCapture).toBeVisible();
    await expect(entryText).toBeFocused();
    await page.waitForTimeout(250);
    const dialogLeft = await quickCapture.evaluate(
      (element) => element.getBoundingClientRect().left,
    );
    const entryTextLeft = await entryText.evaluate(
      (element) => element.getBoundingClientRect().left,
    );
    expect(Math.round(entryTextLeft - dialogLeft)).toBe(21);
    const dialogMarkLeft = await dialogHeader
      .locator("span")
      .first()
      .evaluate((element) => element.getBoundingClientRect().left);
    const dateActionLeft = await quickCapture
      .getByRole("button", { name: "Date", exact: true })
      .evaluate((element) => element.getBoundingClientRect().left);
    expect(Math.round(dialogMarkLeft)).toBe(Math.round(entryTextLeft));
    expect(Math.round(dateActionLeft)).toBe(Math.round(entryTextLeft));
    const dialogRight = await quickCapture.evaluate(
      (element) => element.getBoundingClientRect().right,
    );
    const closeRight = await quickCapture
      .getByRole("button", { name: "Close quick capture", exact: true })
      .evaluate((element) => element.getBoundingClientRect().right);
    const saveRight = await quickCapture
      .getByRole("button", { name: "Save", exact: true })
      .evaluate((element) => element.getBoundingClientRect().right);
    expect(Math.round(dialogRight - closeRight)).toBe(21);
    expect(Math.round(dialogRight - saveRight)).toBe(21);
    const entryTextStyle = await entryText.evaluate((element) => {
      const style = getComputedStyle(element);
      return {
        borderWidth: style.borderWidth,
        boxShadow: style.boxShadow,
        caretColor: style.caretColor,
        outlineStyle: style.outlineStyle,
        resize: style.resize,
      };
    });
    expect(entryTextStyle).toMatchObject({
      borderWidth: "0px",
      boxShadow: "none",
      outlineStyle: "none",
      resize: "none",
    });
    expect(entryTextStyle.caretColor).not.toBe("rgba(0, 0, 0, 0)");
    const emptyTextMetrics = await entryText.evaluate((element) => ({
      height: element.getBoundingClientRect().height,
      lineHeight: Number.parseFloat(getComputedStyle(element).lineHeight),
    }));
    expect(emptyTextMetrics.height).toBeGreaterThanOrEqual(
      emptyTextMetrics.lineHeight * 3,
    );
    const formatting = quickCapture.getByRole("toolbar", {
      name: "Text formatting",
      exact: true,
    });
    for (const [label, shortcut, ariaShortcut] of [
      ["Bold", "⌘B", /Meta\+B/],
      ["Italic", "⌘I", /Meta\+I/],
      ["Underline", "⌘U", /Meta\+U/],
      ["Strikethrough", "⌘⇧S", /Meta\+Shift\+S/],
      ["Attach link", "⌘K", /Meta\+K/],
      ["Bullet list", "⌘⇧8", /Meta\+Shift\+8/],
      ["Ordered list", "⌘⇧7", /Meta\+Shift\+7/],
      ["Block quote", "⌘⇧B", /Meta\+Shift\+B/],
      ["Inline code", "⌘E", /Meta\+E/],
      ["Code block", "⌘⌥C", /Meta\+Alt\+C/],
    ] as const) {
      const button = formatting.getByRole("button", {
        name: label,
        exact: true,
      });
      await expect(button).toBeVisible();
      await expect(button).toHaveAttribute("aria-keyshortcuts", ariaShortcut);
      await button.hover();
      const tooltip = button.getByRole("tooltip");
      await expect(tooltip).toBeVisible();
      await expect(tooltip).toContainText(label);
      await expect(tooltip).toContainText(shortcut);
    }
    const boldButton = formatting.getByRole("button", {
      name: "Bold",
      exact: true,
    });
    await boldButton.hover();
    await expect(boldButton.getByRole("tooltip")).toHaveCSS("opacity", "1");
    await page.screenshot({
      caret: "initial",
      path: test.info().outputPath("memotrail-rich-text-tooltip.png"),
    });
    const entryBody = "A small moment worth keeping.";
    await entryText.fill("List item");
    await entryText.press("ControlOrMeta+Shift+8");
    await expect(entryText.locator("ul")).toContainText("List item");
    await entryText.press("ControlOrMeta+Shift+8");
    await expect(entryText.locator("ul")).toHaveCount(0);
    await entryText.fill(entryBody);
    for (const [label, element] of [
      ["Bold", "strong"],
      ["Italic", "em"],
      ["Underline", "u"],
      ["Strikethrough", "s"],
      ["Inline code", "code"],
    ] as const) {
      await entryText.press("ControlOrMeta+a");
      const button = formatting.getByRole("button", {
        name: label,
        exact: true,
      });
      await button.click();
      await expect(entryText.locator(element)).toHaveText(entryBody);
      await button.click();
      await expect(entryText.locator(element)).toHaveCount(0);
    }
    await entryText.press("ControlOrMeta+a");
    await formatting.getByRole("button", { name: "Bold", exact: true }).click();
    await entryText.press("ControlOrMeta+k");
    await expect(commandPalette).not.toBeVisible();
    await quickCapture
      .getByRole("textbox", { name: "Link URL" })
      .fill("example.com/memory");
    await quickCapture.getByRole("button", { name: "Apply" }).click();
    await expect(entryText.locator("a")).toHaveAttribute(
      "href",
      "https://example.com/memory",
    );
    await expect(entryText).toContainText(entryBody);
    await expect
      .poll(() =>
        page.evaluate((ownerId) => {
          const stored = localStorage.getItem(
            `memotrail:inbox-draft:${ownerId}`,
          );
          return stored ? JSON.parse(stored) : null;
        }, owner),
      )
      .toMatchObject({
        body: entryBody,
        bodyRich: { text: entryBody, version: 1 },
      });
    expect(
      await entryText.evaluate(
        (element) => element.getBoundingClientRect().height,
      ),
    ).toBeGreaterThanOrEqual(emptyTextMetrics.height);
    await page.screenshot({
      caret: "initial",
      path: test.info().outputPath("memotrail-quick-capture-typing.png"),
    });
    await quickCapture
      .getByRole("button", { name: "Save", exact: true })
      .click();
    await expect(quickCaptureForm).not.toContainText(
      "MemoTrail could not store this Entry",
    );
    await expect(
      page
        .locator("[data-sonner-toast]")
        .filter({ hasText: "Saved to Library." }),
    ).toBeVisible();
    await expect
      .poll(async () => {
        const result = await client
          .from("entries")
          .select("body,metadata")
          .eq("owner_id", owner)
          .eq("body", entryBody)
          .maybeSingle();
        return { data: result.data, error: result.error };
      })
      .toMatchObject({
        data: {
          body: entryBody,
          metadata: {
            body_rich: {
              text: entryBody,
              version: 1,
            },
          },
        },
        error: null,
      });

    await quickCapture
      .getByRole("button", { name: "Close quick capture", exact: true })
      .click();
    await primaryNavigation
      .getByRole("link", { name: "Library", exact: true })
      .click();
    await expect(page).toHaveURL(/\/library$/);
    await primaryNavigation
      .getByRole("link", { name: "Tags", exact: true })
      .click();
    await expect(page).toHaveURL(/\/tags$/);
    await expect(goForward).toBeDisabled();
    await goBack.click();
    await expect(page).toHaveURL(/\/library$/);
    await expect(goForward).toBeEnabled();
    await goForward.click();
    await expect(page).toHaveURL(/\/tags$/);
    await goBack.click();
    await expect(page).toHaveURL(/\/library$/);
    await page.goto("/tags");
    await expect(page).toHaveURL(/\/tags$/);
    await expect(goBack).toBeEnabled();
    await goBack.click();
    await expect(page).toHaveURL(/\/library$/);
    await expect(goForward).toBeEnabled();
    await goForward.click();
    await expect(page).toHaveURL(/\/tags$/);
    await page.goBack();
    await expect(page).toHaveURL(/\/library$/);
  } finally {
    releaseMapNavigation();
    await page.close();
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
