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
      .getByRole("navigation", { name: "Workspace tools" })
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
    // Sign out is a secondary button in the last section, not the page's primary action.
    await expect(
      main.getByRole("button", { name: "Sign out", exact: true }),
    ).toHaveAttribute("data-variant", "secondary");
    await expect(main.getByRole("heading", { level: 2 })).toHaveText([
      "Profile",
      "Time",
      "Appearance",
      "Reviews",
      "Your data",
      "Account",
    ]);
    // Each row leads to its page with a secondary button.
    await expect(main.getByRole("link", { name: "Import" })).toHaveAttribute(
      "href",
      "/settings/import",
    );
    await expect(main.getByRole("link", { name: "Export" })).toHaveAttribute(
      "href",
      "/settings/export",
    );
    await expect(main.getByRole("link", { name: "Open Tags" })).toHaveAttribute(
      "href",
      "/tags",
    );
    await expect(main).not.toContainText(/archive/i);
    // The paused AI capabilities row is gone; the review switches take its place.
    await expect(
      page.getByRole("link", { name: /AI capabilities/ }),
    ).toHaveCount(0);
    await expect(
      main.getByRole("checkbox", { name: "Chapter and year reviews" }),
    ).not.toBeChecked();
    await expect(
      main.getByRole("checkbox", { name: "Suggest Chapters" }),
    ).not.toBeChecked();
    // This suite runs without an embedding service, so search is keyword-only.
    await expect(
      main.getByRole("checkbox", { name: "Search by meaning" }),
    ).toHaveCount(0);

    const preferredName = main.getByRole("textbox", {
      name: "Preferred name",
    });
    await expect(preferredName).toHaveValue(displayName);
    for (const field of [
      preferredName,
      main.getByRole("textbox", { name: "Birth date" }),
      main.getByRole("combobox", { name: "Default time zone" }),
    ]) {
      await expect(field).toHaveCSS("font-size", "13px");
    }
    await page.screenshot({
      animations: "disabled",
      caret: "initial",
      path: test
        .info()
        .outputPath("memotrail-settings-preferred-name-desktop.png"),
    });
    // A field saves when it loses focus, and says so beside itself.
    const nameRow = main.locator("[data-setting-row]").filter({
      has: page.getByRole("textbox", { name: "Preferred name" }),
    });
    await expect(nameRow).not.toContainText("Saved");
    await preferredName.fill("River");
    await preferredName.press("Tab");
    await expect(nameRow).toContainText("Saved");
    await expect(main.getByRole("button", { name: "Save name" })).toHaveCount(
      0,
    );
    await expect
      .poll(
        async () =>
          (
            await client
              .from("profiles")
              .select("display_name")
              .eq("user_id", owner)
              .single()
          ).data?.display_name,
      )
      .toBe("River");
    await page.goto("/");
    await expect(page.getByRole("main").locator("h1")).toHaveText(/, River$/);
    await page.goto("/settings");
    await expect(main.getByText("River", { exact: true })).toBeVisible();
    await preferredName.fill("");
    await expect(preferredName).toHaveValue("");
    await preferredName.press("Enter");
    await expect(nameRow).toContainText("Saved");
    await expect
      .poll(
        async () =>
          (
            await client
              .from("profiles")
              .select("display_name")
              .eq("user_id", owner)
              .single()
          ).data?.display_name,
      )
      .toBeNull();
    await page.goto("/");
    await expect(page.getByRole("main").locator("h1")).toHaveText(
      /, Settings$/,
    );
    await page.goto("/settings");

    const appearance = main.getByRole("group", { name: "Theme", exact: true });
    const appearanceRow = main.locator("[data-setting-row]").filter({
      has: page.getByRole("group", { name: "Theme", exact: true }),
    });
    const systemTheme = appearance.getByRole("radio", { name: "System" });
    const lightTheme = appearance.getByRole("radio", { name: "Light" });
    const darkTheme = appearance.getByRole("radio", { name: "Dark" });
    await expect(systemTheme).toBeChecked();
    await expect(page.locator("html")).not.toHaveAttribute("data-theme");
    await darkTheme.check();
    await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
    await expect(darkTheme).toBeChecked();
    await expect(appearanceRow).toContainText("Saved");
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
    await expect(appearance).toBeEnabled();
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
    await expect(appearance).toBeEnabled();
    await expect
      .poll(() =>
        page.evaluate(
          () => getComputedStyle(document.documentElement).colorScheme,
        ),
      )
      .toBe("dark");
    await page.screenshot({
      animations: "disabled",
      caret: "initial",
      fullPage: true,
      path: test.info().outputPath("memotrail-settings-appearance-dark.png"),
    });
    await page.emulateMedia({ colorScheme: "light" });
    await expect
      .poll(() =>
        page.evaluate(
          () => getComputedStyle(document.documentElement).colorScheme,
        ),
      )
      .toBe("light");

    // Offline, a failed save is reported where it happened; Settings stays.
    await context.setOffline(true);
    // click, not check: the failed save puts System back, possibly before check() could see Dark.
    await darkTheme.click();
    await expect(
      page.getByText("Appearance could not be saved", { exact: false }).first(),
    ).toBeVisible();
    await expect(main.locator("h1")).toHaveText("Settings");
    await expect(page.getByText("This page couldn't load")).toHaveCount(0);
    await expect(systemTheme).toBeChecked();
    await expect(page.locator("html")).not.toHaveAttribute("data-theme");
    await expect(appearance).toBeEnabled();
    await context.setOffline(false);

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
    // Choosing a zone saves it, with no button.
    await timezone.selectOption("America/Los_Angeles");
    await expect(
      main.locator("[data-setting-row]").filter({
        has: page.getByRole("combobox", { name: "Default time zone" }),
      }),
    ).toContainText("Saved");
    await expect(
      main.getByRole("button", { name: "Save time zone" }),
    ).toHaveCount(0);
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
      caret: "initial",
      animations: "disabled",
      path: test.info().outputPath("memotrail-settings-desktop.png"),
    });

    await page.setViewportSize({ width: 390, height: 844 });
    await expect(
      page.getByRole("link", { name: `Open settings for ${displayName}` }),
    ).toHaveAttribute("aria-current", "page");
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.screenshot({
      caret: "initial",
      animations: "disabled",
      path: test.info().outputPath("memotrail-settings-mobile.png"),
    });

    await page.getByRole("button", { name: "Sign out", exact: true }).click();
    await expect(page).toHaveURL(/\/$/);
    await expect(
      page.getByRole("heading", {
        name: "The one private place your life is written down.",
      }),
    ).toBeVisible();
  } finally {
    await page.close();
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
