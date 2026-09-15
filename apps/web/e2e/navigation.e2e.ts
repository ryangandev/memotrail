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
    await expect(newEntryShortcut).not.toContainText("New entry");
    const topActionStyle = async (button: typeof searchShortcut) =>
      button.evaluate((element) => {
        const style = getComputedStyle(element);
        return {
          backgroundColor: style.backgroundColor,
          borderColor: style.borderColor,
          boxShadow: style.boxShadow,
          color: style.color,
          height: style.height,
        };
      });
    const searchActionStyle = await topActionStyle(searchShortcut);
    expect(await topActionStyle(newEntryShortcut)).toEqual(searchActionStyle);
    await newEntryShortcut.hover();
    await expect
      .poll(async () => (await topActionStyle(newEntryShortcut)).boxShadow)
      .not.toBe(searchActionStyle.boxShadow);
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-topbar-action-hover.png",
    });
    await page.mouse.move(500, 500);
    await expect
      .poll(async () => (await topActionStyle(newEntryShortcut)).boxShadow)
      .toBe(searchActionStyle.boxShadow);
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
    await page.emulateMedia({ colorScheme: "dark" });
    await page.keyboard.press("Meta+j");

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
    const dialogHeader = quickCapture.locator("header");
    await expect(dialogHeader).toHaveCSS("border-bottom-width", "0px");
    await expect(dialogHeader.locator("svg")).toHaveCount(1);
    expect(
      await dialogHeader.evaluate(
        (element) => element.getBoundingClientRect().height,
      ),
    ).toBeLessThanOrEqual(56);
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
    const dialogLeft = await quickCapture.evaluate(
      (element) => element.getBoundingClientRect().left,
    );
    const entryTextLeft = await entryText.evaluate(
      (element) => element.getBoundingClientRect().left,
    );
    expect(Math.round(entryTextLeft - dialogLeft)).toBe(21);
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
    for (const label of [
      "Bold",
      "Italic",
      "Underline",
      "Strikethrough",
      "Attach link",
      "Bullet list",
      "Ordered list",
      "Block quote",
      "Inline code",
      "Code block",
    ]) {
      await expect(
        formatting.getByRole("button", { name: label, exact: true }),
      ).toBeVisible();
    }
    const entryBody = "A small moment worth keeping.";
    await entryText.fill(entryBody);
    for (const [label, element] of [
      ["Bold", "strong"],
      ["Italic", "em"],
      ["Underline", "u"],
      ["Strikethrough", "s"],
      ["Inline code", "code"],
    ] as const) {
      await entryText.press("Meta+a");
      const button = formatting.getByRole("button", {
        name: label,
        exact: true,
      });
      await button.click();
      await expect(entryText.locator(element)).toHaveText(entryBody);
      await button.click();
      await expect(entryText.locator(element)).toHaveCount(0);
    }
    await entryText.press("Meta+a");
    await formatting
      .getByRole("button", { name: "Bold", exact: true })
      .click();
    await formatting
      .getByRole("button", { name: "Attach link", exact: true })
      .click();
    await quickCapture.getByRole("textbox", { name: "Link URL" }).fill(
      "example.com/memory",
    );
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
      path: "/private/tmp/memotrail-quick-capture-typing.png",
    });
    await quickCapture
      .getByRole("button", { name: "Save to Inbox", exact: true })
      .click();
    await expect(quickCaptureForm).not.toContainText(
      "MemoTrail could not store this Entry",
    );
    await expect(quickCaptureForm).toContainText("Saved to Inbox.");
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
  } finally {
    await page.close();
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
