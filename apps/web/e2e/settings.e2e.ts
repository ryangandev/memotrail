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

    const appearance = main.getByRole("group", { name: "Appearance mode" });
    const systemTheme = appearance.getByRole("radio", { name: "System" });
    const lightTheme = appearance.getByRole("radio", { name: "Light" });
    const darkTheme = appearance.getByRole("radio", { name: "Dark" });
    await expect(systemTheme).toBeChecked();
    await expect(page.locator("html")).not.toHaveAttribute("data-theme");
    await darkTheme.check();
    await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
    await expect(darkTheme).toBeChecked();
    await expect(appearance).toHaveAttribute("aria-busy", "false");
    await expect
      .poll(() =>
        page.evaluate(
          () => getComputedStyle(document.documentElement).colorScheme,
        ),
      )
      .toBe("dark");
    await page.reload();
    await expect(darkTheme).toBeChecked();
    await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
    await lightTheme.check();
    await expect(page.locator("html")).toHaveAttribute("data-theme", "light");
    await expect(appearance).toHaveAttribute("aria-busy", "false");
    await expect
      .poll(() =>
        page.evaluate(
          () => getComputedStyle(document.documentElement).colorScheme,
        ),
      )
      .toBe("light");
    await page.emulateMedia({ colorScheme: "dark" });
    await systemTheme.check();
    await expect(page.locator("html")).not.toHaveAttribute("data-theme");
    await expect(appearance).toHaveAttribute("aria-busy", "false");
    await expect
      .poll(() =>
        page.evaluate(
          () => getComputedStyle(document.documentElement).colorScheme,
        ),
      )
      .toBe("dark");
    await page.screenshot({
      caret: "initial",
      fullPage: true,
      path: "/private/tmp/memotrail-settings-appearance-dark.png",
    });
    await page.emulateMedia({ colorScheme: "light" });
    await expect
      .poll(() =>
        page.evaluate(
          () => getComputedStyle(document.documentElement).colorScheme,
        ),
      )
      .toBe("light");

    const timezone = main.getByRole("combobox", {
      name: "Default time zone",
      exact: true,
    });
    await expect(timezone).toHaveValue("UTC");
    const timezoneOptions = await timezone.locator("option").allTextContents();
    expect(timezoneOptions.length).toBeGreaterThan(100);
    expect(timezoneOptions.every((label) => label.startsWith("(UTC"))).toBe(
      true,
    );
    await expect(timezone.locator('option[value="UTC"]')).toHaveText(
      "(UTC+00:00) UTC",
    );
    await timezone.selectOption("America/Los_Angeles");
    await main
      .getByRole("button", { name: "Save time zone", exact: true })
      .click();
    await expect(main.getByRole("status")).toHaveText(
      "Default time zone saved.",
    );
    await expect
      .poll(
        async () =>
          (
            await client
              .from("profiles")
              .select("timezone")
              .eq("user_id", owner)
              .single()
          ).data?.timezone,
      )
      .toBe("America/Los_Angeles");

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
