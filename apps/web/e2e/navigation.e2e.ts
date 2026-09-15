import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

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

    let searchNavigationStarted = false;

    await page.route("**/search*", async (route) => {
      const headers = route.request().headers();
      const isRscRequest =
        headers.rsc === "1" ||
        new URL(route.request().url()).searchParams.has("_rsc");

      if (isRscRequest && !searchNavigationStarted) {
        await route.fulfill({
          body: "Search prefetch intentionally unavailable during this test.",
          contentType: "text/plain",
          status: 503,
        });
        return;
      }

      if (isRscRequest) {
        await new Promise((resolve) => setTimeout(resolve, 800));
      }

      await route.continue();
    });
    await page.goto("/");

    const shell = page.getByRole("complementary");
    await expect(shell).toBeVisible();
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
    await expect(shell.getByText(email, { exact: true })).toHaveCount(0);
    await expect(
      shell
        .getByRole("navigation", { name: "Settings navigation" })
        .getByRole("link", { name: "Settings", exact: true }),
    ).toHaveCount(1);
    const syncNote = shell.getByRole("note", { name: "Private cloud sync" });
    await expect(syncNote).toBeVisible();
    await syncNote
      .getByRole("button", { name: "Dismiss private cloud sync" })
      .click();
    await expect(syncNote).not.toBeVisible();
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
    expect(dividerMargins[2]).toEqual(dividerMargins[0]);
    await shell.evaluate((element) => {
      element.setAttribute("data-shell-instance", "kept");
    });

    await page.setViewportSize({ width: 1280, height: 560 });
    const scrollRegion = page.getByRole("region", {
      name: "Sidebar navigation",
    });
    const brand = shell.getByRole("link", { name: "MemoTrail", exact: true });
    const homeLink = shell
      .getByRole("navigation", { name: "Primary navigation" })
      .getByRole("link", { name: "Home", exact: true });
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
    expect(Math.round(scrollRegionRight - homeRight)).toBe(16);
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
      path: "/private/tmp/memotrail-sidebar-scroll.png",
    });
    expect(
      await brand.evaluate((element) => element.getBoundingClientRect().top),
    ).toBe(brandTop);
    expect(
      await capture.evaluate((element) => element.getBoundingClientRect().top),
    ).toBe(captureTop);
    await page.setViewportSize({ width: 1280, height: 720 });

    await page.keyboard.press("Meta+k");
    const commandPalette = page.getByRole("dialog", {
      name: "Search MemoTrail",
    });
    await expect(commandPalette).toBeVisible();
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-command-palette.png",
    });
    await expect(page).toHaveURL(/\/$/);
    await expect(commandPalette.getByRole("searchbox")).toBeFocused();
    await commandPalette.getByRole("searchbox").fill("settings");
    await expect(
      commandPalette.getByRole("button", { name: /Settings/ }),
    ).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(commandPalette).not.toBeVisible();

    searchNavigationStarted = true;
    await page
      .getByRole("navigation", { name: "Primary navigation" })
      .getByRole("link", { name: "Search", exact: true })
      .click({ noWaitAfter: true });

    await expect(
      page.getByRole("status", { name: "Opening Search" }),
    ).toBeVisible({ timeout: 500 });
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-navigation-loading.png",
    });
    await expect(shell).toHaveAttribute("data-shell-instance", "kept");
    await expect(page).toHaveURL(/\/search$/);
    await expect(
      page.getByRole("heading", { name: "Search your trail", exact: true }),
    ).toBeVisible();

    await page
      .getByRole("navigation", { name: "Primary navigation" })
      .getByRole("link", { name: "Inbox", exact: true })
      .click();
    await expect(page).toHaveURL(/\/inbox$/);
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
    await page.keyboard.press("Meta+j");

    const quickCapture = page.getByRole("dialog", {
      name: "Keep what is on your mind",
    });
    const entryText = quickCapture.getByRole("textbox", {
      name: "Entry text",
      exact: true,
    });
    await expect(quickCapture).toBeVisible();
    await expect(
      quickCapture.getByRole("textbox", {
        name: "Entry title",
        exact: true,
      }),
    ).toHaveCount(0);
    await expect(entryText).toBeEnabled();
    await expect(entryText).toBeFocused();
    const entryTextStyle = await entryText.evaluate((element) => {
      const style = getComputedStyle(element);
      return {
        borderWidth: style.borderWidth,
        boxShadow: style.boxShadow,
        caretColor: style.caretColor,
        outlineStyle: style.outlineStyle,
      };
    });
    expect(entryTextStyle).toMatchObject({
      borderWidth: "0px",
      boxShadow: "none",
      outlineStyle: "none",
    });
    expect(entryTextStyle.caretColor).not.toBe("rgba(0, 0, 0, 0)");
    await entryText.fill("Typing stays visible without a focus border.");
    await expect(entryText).toHaveValue(
      "Typing stays visible without a focus border.",
    );
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-quick-capture-typing.png",
    });
  } finally {
    await page.close();
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
