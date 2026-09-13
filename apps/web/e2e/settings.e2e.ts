import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

test("Settings is reachable from the sidebar and owns account controls", async ({
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
  const email = `settings-${randomUUID()}@memotrail.local`;
  const displayName = "Settings Tester";
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
    user_metadata: { full_name: displayName },
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

    await page.goto("/");
    await page
      .getByRole("navigation", { name: "Settings navigation" })
      .getByRole("link", { name: "Settings", exact: true })
      .click();

    await expect(page).toHaveURL(/\/settings$/);
    await expect(
      page.getByRole("heading", { name: "Settings", exact: true }),
    ).toBeVisible();
    const main = page.getByRole("main");
    await expect(main.getByText(email, { exact: true })).toBeVisible();
    await expect(
      main.getByText("Google Sign-In", { exact: true }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: /AI assistance/ }),
    ).toHaveAttribute("href", "/settings/ai");

    await page.screenshot({
      path: "/private/tmp/memotrail-settings-desktop.png",
    });

    await page.setViewportSize({ width: 390, height: 844 });
    await expect(
      page.getByRole("link", { name: `Open settings for ${displayName}` }),
    ).toHaveAttribute("aria-current", "page");
    await page.screenshot({
      fullPage: true,
      path: "/private/tmp/memotrail-settings-mobile.png",
    });

    await page.getByRole("button", { name: "Sign out", exact: true }).click();
    await expect(page).toHaveURL(/\/$/);
    await expect(
      page.getByRole("heading", { name: "Welcome to MemoTrail" }),
    ).toBeVisible();
  } finally {
    await page.close();
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
