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
        await route.abort("blockedbyclient");
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
    await shell.evaluate((element) => {
      element.setAttribute("data-shell-instance", "kept");
    });

    await page.setViewportSize({ width: 1280, height: 560 });
    const scrollRegion = page.getByRole("region", {
      name: "Sidebar navigation",
    });
    const brand = shell.getByRole("link", { name: "MemoTrail", exact: true });
    const capture = shell.getByRole("link", {
      name: "New entry",
      exact: true,
    });
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
  } finally {
    await page.close();
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
