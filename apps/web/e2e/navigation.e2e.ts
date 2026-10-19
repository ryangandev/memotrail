import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test, type Locator } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";
import { test as workspaceTest } from "./helpers/workspace-test";

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
  // Collapsed, the brand link leaves the accessibility tree, so find it by its label.
  const brand = toggle
    .page()
    .locator('aside a[aria-label="MemoTrail dashboard"]');
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
  let releaseSlowNavigation = () => {};
  const slowNavigationGate = new Promise<void>((resolve) => {
    releaseSlowNavigation = resolve;
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

    let slowNavigationStarted = false;

    await page.route("**/timeline*", async (route) => {
      const headers = route.request().headers();
      const isRscRequest =
        headers.rsc === "1" ||
        new URL(route.request().url()).searchParams.has("_rsc");

      if (isRscRequest && !slowNavigationStarted) {
        await route.fulfill({
          body: "Timeline prefetch intentionally unavailable during this test.",
          contentType: "text/plain",
          status: 503,
        });
        return;
      }

      if (isRscRequest) {
        await slowNavigationGate;
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
    const workspaceTools = shell.getByRole("navigation", {
      name: "Workspace tools",
    });
    // Three groups without labels: the daily places, the focused views after a rule, and the
    // tools at the sidebar's foot.
    await expect(primaryNavigation.getByRole("link")).toHaveText([
      "Dashboard",
      "Timeline",
      "Library",
      "First Times",
      "Reviews",
      "Tags",
    ]);
    await expect(workspaceTools.getByRole("link")).toHaveText([
      "Import",
      "Trash",
      "Settings",
    ]);
    for (const label of ["Focused views", "Organize", "Navigation"])
      await expect(shell.getByText(label, { exact: true })).toHaveCount(0);
    // Homes and Vehicles are Chapters now, and captures land in Library, so none has a link.
    for (const name of ["Homes", "Vehicles", "Inbox"])
      await expect(shell.getByRole("link", { name, exact: true })).toHaveCount(
        0,
      );
    // The current destination is the raised row with a hairline ring.
    const dashboardLink = primaryNavigation.getByRole("link", {
      name: "Dashboard",
      exact: true,
    });
    await expect(dashboardLink).toHaveAttribute("aria-current", "page");
    await expect(dashboardLink).toHaveCSS("box-shadow", /0px 0px 0px 1px/);
    // Desktop has no top bar and so no history arrows; the panel control follows the logo.
    await expect(page.locator("main > header")).toBeHidden();
    await expect(page.getByRole("button", { name: "Go back" })).toHaveCount(0);
    await expect(page.getByRole("button", { name: "Go forward" })).toHaveCount(
      0,
    );
    const panelControl = shell.getByRole("button", {
      name: "Collapse sidebar",
    });
    await page.keyboard.press("Tab");
    await expect(panelControl).toBeFocused();
    await expect(panelControl).toHaveCSS("outline-style", "none");
    await expect(panelControl).toHaveCSS("box-shadow", /inset/);
    await primaryNavigation
      .getByRole("link", { name: "Library", exact: true })
      .click();
    await expect(page).toHaveURL(/\/library$/);
    await expect(
      primaryNavigation.getByRole("link", { name: "Library", exact: true }),
    ).toHaveAttribute("aria-current", "page");
    await page.goBack();
    await expect(page).toHaveURL(/\/$/);
    await expect(shell.getByRole("button", { name: "New entry" })).toHaveCount(
      0,
    );
    // The account row at the sidebar's foot says the workspace is synced.
    await expect(shell.getByText("Synced", { exact: true })).toBeVisible();
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
    await expect(page.getByRole("link", { name: /Inbox/ })).toHaveCount(0);
    const [dockBox, searchBox] = await Promise.all([
      newEntryShortcut.boundingBox(),
      searchShortcut.boundingBox(),
    ]);
    expect(dockBox!.x + dockBox!.width).toBeLessThan(searchBox!.x);
    expect(dockBox!.y).toBeCloseTo(searchBox!.y, 0);
    await expect(newEntryShortcut).toHaveCSS("backdrop-filter", /blur/);
    await expect(shell.getByText(email, { exact: true })).toHaveCount(0);
    await expect(
      workspaceTools.getByRole("link", { name: "Settings", exact: true }),
    ).toHaveCount(1);
    await expect(
      shell.getByRole("note", { name: "Private cloud sync" }),
    ).toHaveCount(0);
    await page.reload();
    await expect(
      shell.getByRole("note", { name: "Private cloud sync" }),
    ).toHaveCount(0);
    // One rule separates the daily places from the focused views.
    await expect(shell.getByRole("separator")).toHaveCount(1);
    await shell.evaluate((element) => {
      element.setAttribute("data-shell-instance", "kept");
    });

    await page.setViewportSize({ width: 1280, height: 560 });
    const scrollRegion = page.getByRole("region", {
      name: "Sidebar navigation",
    });
    // Collapsed, the brand link leaves the accessibility tree, so find it by its label.
    const brand = shell.locator('a[aria-label="MemoTrail dashboard"]');
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
    expect(Math.round(homeIconLeft - brandMarkLeft)).toBe(2);
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
      workspaceTools.getByRole("link", { name: "Settings", exact: true }),
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
    // Collapsed, the logo is the toggle's resting face: only the toggle is reachable, and it
    // shows itself over the logo on focus.
    const expandSidebar = shell.getByRole("button", {
      name: "Expand sidebar",
    });
    await expect(
      shell.getByRole("link", { name: "MemoTrail dashboard" }),
    ).toHaveCount(0);
    await homeLink.focus();
    await page.keyboard.press("Shift+Tab");
    await expect(expandSidebar).toBeFocused();
    await expect(expandSidebar).toHaveCSS("opacity", "1");
    await expect(expandSidebar).toHaveCSS("box-shadow", /inset/);
    const logoBox = await shell
      .locator('a[aria-label="MemoTrail dashboard"] svg')
      .boundingBox();
    expect(logoBox?.width).toBe(24);
    expect(logoBox?.height).toBe(24);
    await expect(homeLink.locator("svg")).toHaveCSS("width", "18px");
    await expect(homeLink.locator("svg")).toHaveCSS("height", "18px");
    expect(
      Math.abs(
        (logoBox?.x ?? 0) +
          (logoBox?.width ?? 0) / 2 -
          ((activeHomeBox?.x ?? 0) + (activeHomeBox?.width ?? 0) / 2),
      ),
    ).toBeLessThanOrEqual(1);
    await expect(expandSidebar.locator("svg")).toHaveAttribute("width", "18");
    await expect(expandSidebar.locator("svg")).toHaveAttribute("height", "18");
    const collapsedLibrary = primaryNavigation.getByRole("link", {
      name: "Library",
      exact: true,
    });
    await expect(collapsedLibrary).toBeVisible();
    await expect(homeLink).toHaveCSS("width", "36px");
    await expect(homeLink).toHaveCSS("height", "36px");
    await collapsedLibrary.hover();
    await expect(collapsedLibrary).toHaveCSS("width", "36px");
    await expect(collapsedLibrary).toHaveCSS("height", "36px");
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
    for (const label of ["Dashboard", "Timeline", "Library"]) {
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
    await expect(mobileNavigation.locator(":scope > *")).toHaveCount(4);
    await expect(mobileNavigation.locator(":scope > *")).toHaveText([
      "Dashboard",
      "Timeline",
      "Library",
      "More",
    ]);
    // The phone top bar is 48 px with the logo, the sync status, and a 32 px avatar, and no
    // history arrows.
    const topBar = page.locator("main > header");
    await expect(topBar).toHaveCSS("height", "48px");
    await expect(topBar.getByText("Synced", { exact: true })).toBeVisible();
    await expect(
      topBar.getByRole("link", { name: /^Open settings for / }),
    ).toHaveCSS("width", "32px");
    await expect(page.getByRole("button", { name: "Go back" })).toHaveCount(0);
    const moreButton = mobileNavigation.getByRole("button", {
      name: "More destinations",
    });
    await moreButton.click();
    const moreDestinations = page.getByRole("navigation", {
      name: "More destinations",
    });
    await expect(moreDestinations).toBeVisible();
    // More is a plain list of every other destination, in sidebar order.
    await expect(moreDestinations.getByRole("link")).toHaveText([
      "First Times",
      "Reviews",
      "Tags",
      "Import",
      "Trash",
      "Settings",
    ]);
    await expect(moreDestinations.locator("svg")).toHaveCount(0);
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
    await expect(shell).toHaveCSS("width", "240px");
    await expect(page.locator("main")).toHaveCSS("margin-left", "240px");
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

    slowNavigationStarted = true;
    await page
      .getByRole("navigation", { name: "Primary navigation" })
      .getByRole("link", { name: "Timeline", exact: true })
      .click({ noWaitAfter: true });

    await expect(
      page.getByRole("status", { name: "Opening Timeline" }),
    ).toBeVisible();
    await page.screenshot({
      caret: "initial",
      path: test.info().outputPath("memotrail-navigation-loading.png"),
    });
    await expect(shell).toHaveAttribute("data-shell-instance", "kept");
    releaseSlowNavigation();
    await expect(page).toHaveURL(/\/timeline$/);
    await expect(
      page.getByRole("heading", { name: "Timeline", exact: true }),
    ).toBeVisible();

    await workspaceTools
      .getByRole("link", { name: "Settings", exact: true })
      .click();
    await expect(page).toHaveURL(/\/settings$/);
    await expect(shell).toHaveAttribute("data-shell-instance", "kept");

    await page
      .getByRole("navigation", { name: "Primary navigation" })
      .getByRole("link", { name: "Timeline", exact: true })
      .click();
    await expect(page).toHaveURL(/\/timeline$/);
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
    await page.goBack();
    await expect(page).toHaveURL(/\/library$/);
    await page.goForward();
    await expect(page).toHaveURL(/\/tags$/);
  } finally {
    releaseSlowNavigation();
    await page.close();
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});

workspaceTest(
  "retired Homes and Vehicles addresses open Timeline or the Chapter's Item page",
  async ({ page, workspace: { client, owner } }) => {
    const chapter = randomUUID();
    expect(
      (
        await client.from("entries").insert({
          id: chapter,
          owner_id: owner,
          title: "Maple Street flat",
          body: "",
          item_kind: "entry",
          item_subtype: "chapter",
          occurred_start: "2021-06-01T12:00:00+00:00",
          occurred_end: null,
          occurred_timezone: "UTC",
          date_precision: "day",
        })
      ).error,
    ).toBeNull();

    for (const path of ["/homes", "/vehicles", `/vehicles/${randomUUID()}`]) {
      await page.goto(path);
      await expect(page).toHaveURL(/\/timeline$/);
    }
    await page.goto("/homes/not-an-id");
    await expect(page).toHaveURL(/\/timeline$/);
    await page.goto(`/homes/${chapter}`);
    await expect(page).toHaveURL(`/items/${chapter}`);
    await expect(
      page.getByRole("heading", { name: "Maple Street flat" }),
    ).toBeVisible();
    await page.goto(`/vehicles/${chapter}/edit`);
    await expect(page).toHaveURL(/\/timeline$/);
  },
);
