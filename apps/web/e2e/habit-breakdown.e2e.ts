import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("Habit monthly and weekday summaries reflect canonical statuses without penalizing skips", async ({
  page,
  context,
}) => {
  const env = JSON.parse(
    execFileSync("supabase", ["status", "-o", "json"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }),
  );
  expect(env.API_URL).toBe("http://127.0.0.1:54321");
  const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
  const email = `habit-breakdown-${randomUUID()}@memotrail.local`;
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
      cookies.map((c) => ({
        ...c,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax" as const,
      })),
    );
    const habit = randomUUID();
    expect(
      (
        await client.from("habits").insert({
          id: habit,
          owner_id: owner,
          name: "Reading practice",
          starts_on: "2024-02-26",
          ends_on: "2024-03-03",
          schedule: { kind: "daily" },
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("habit_occurrences").insert([
          {
            habit_id: habit,
            owner_id: owner,
            local_date: "2024-02-26",
            status: "completed",
          },
          {
            habit_id: habit,
            owner_id: owner,
            local_date: "2024-02-27",
            status: "skipped",
          },
          {
            habit_id: habit,
            owner_id: owner,
            local_date: "2024-02-29",
            status: "completed",
          },
        ])
      ).error,
    ).toBeNull();
    await page.goto(`/habits?habit=${habit}&year=2024&date=2024-03-03`);
    await expect(
      page.getByRole("heading", { name: "Monthly summary", exact: true }),
    ).toBeVisible();
    const monthly = page.getByRole("table", {
      name: "Monthly summary",
      exact: true,
    });
    const weekly = page.getByRole("table", {
      name: "Weekday patterns",
      exact: true,
    });
    await expect(monthly.getByRole("row", { name: /^Feb / })).toHaveText(
      "Feb21167%",
    );
    await expect(monthly.getByRole("row", { name: /^Mar / })).toHaveText(
      "Mar0200%",
    );
    await expect(monthly.getByRole("row", { name: /^Apr / })).toHaveText(
      "Apr000-",
    );
    await expect(weekly.getByRole("row", { name: /^Tuesday / })).toHaveText(
      "Tuesday001-",
    );
    await expect(
      page.getByText("Most misses: Wednesday, Friday, Saturday (1 each).", {
        exact: true,
      }),
    ).toBeVisible();
    await page.setViewportSize({ width: 1440, height: 1200 });
    await page
      .getByRole("heading", { name: "Monthly summary", exact: true })
      .scrollIntoViewIfNeeded();
    await monthly.scrollIntoViewIfNeeded();
    await page.screenshot({
      path: "/private/tmp/memotrail-habit-breakdown-desktop.png",
    });

    await page
      .getByRole("gridcell", { name: /February 28, 2024: Missed/ })
      .click();
    const dialog = page.getByRole("dialog");
    await dialog
      .getByRole("button", { name: "Completed", exact: true })
      .click();
    await dialog
      .getByRole("button", { name: "Save check-in", exact: true })
      .click();
    await expect(dialog).not.toBeVisible();
    await expect(monthly.getByRole("row", { name: /^Feb / })).toHaveText(
      "Feb301100%",
    );
    await expect(
      page.getByText("Most misses: Friday, Saturday (1 each).", {
        exact: true,
      }),
    ).toBeVisible();

    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page
      .getByRole("heading", { name: "Monthly summary", exact: true })
      .scrollIntoViewIfNeeded();
    await monthly.scrollIntoViewIfNeeded();
    await page.screenshot({
      path: "/private/tmp/memotrail-habit-breakdown-mobile.png",
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);
    await weekly.scrollIntoViewIfNeeded();
    await page.screenshot({
      path: "/private/tmp/memotrail-habit-breakdown-weekdays-mobile.png",
    });
    await page.getByRole("button", { name: "Show 2023", exact: true }).click();
    await expect(monthly.getByRole("row", { name: /^Feb / })).toHaveText(
      "Feb000-",
    );
    await expect(
      page.getByText("No missed days in this view.", { exact: true }),
    ).toBeVisible();

    const flexibleHabit = randomUUID();
    expect(
      (
        await client.from("habits").insert({
          id: flexibleHabit,
          owner_id: owner,
          name: "Flexible reading",
          starts_on: "2024-02-26",
          schedule: { kind: "weekly_target", target: 3 },
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("habit_occurrences").insert({
          habit_id: flexibleHabit,
          owner_id: owner,
          local_date: "2024-03-02",
          status: "missed",
        })
      ).error,
    ).toBeNull();
    await page.goto(`/habits?habit=${flexibleHabit}&year=2024&date=2024-03-03`);
    await expect(
      page.getByText(/Weekly targets use recorded check-ins only/),
    ).toBeVisible();
    await expect(monthly.getByRole("row", { name: /^Feb / })).toHaveText(
      "Feb000-",
    );
    await expect(monthly.getByRole("row", { name: /^Mar / })).toHaveText(
      "Mar0100%",
    );
    await expect(
      page.getByText("Most misses: Saturday (1 each).", { exact: true }),
    ).toBeVisible();
  } finally {
    await page.close();
    // Only the isolated local fixture is removed, in trigger-safe dependency order.
    expect(owner).toMatch(/^[0-9a-f-]{36}$/);
    execFileSync(
      "docker",
      [
        "exec",
        "supabase_db_memotrail",
        "psql",
        "-U",
        "postgres",
        "-d",
        "postgres",
        "-v",
        "ON_ERROR_STOP=1",
        "-c",
        `BEGIN; DELETE FROM public.habit_occurrences WHERE owner_id = '${owner}'; DELETE FROM public.habits WHERE owner_id = '${owner}'; COMMIT;`,
      ],
      { stdio: "pipe" },
    );
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
