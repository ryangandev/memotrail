import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import { fillOccurrenceEnd, fillOccurrenceStart } from "./helpers/occurrence";

test("Goal achievements preserve all eight date precisions and reject duplicate completion", async ({
  page,
  context,
}) => {
  const uiErrors: string[] = [];
  page.on("pageerror", (error) => uiErrors.push(error.message));
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
  const email = `goal-achievement-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  const owner = created.data.user!.id;
  try {
    const cookies: { name: string; value: string }[] = [];
    const client = createServerClient(env.API_URL, env.ANON_KEY, {
      cookies: {
        getAll: () => cookies,
        setAll: (values) => {
          cookies.push(
            ...values.map((v) => ({ name: v.name, value: v.value })),
          );
        },
      },
    });
    const link = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    await client.auth.verifyOtp({
      type: "magiclink",
      token_hash: link.data.properties!.hashed_token,
    });
    await context.addCookies(
      cookies.map((c) => ({
        ...c,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax",
        httpOnly: false,
      })),
    );

    const cases = [
      { precision: "age", label: "17岁", start: "", end: "", expected: null },
      {
        precision: "approximate",
        label: "Summer before college",
        start: "",
        end: "",
        expected: null,
      },
      { precision: "unknown", label: "", start: "", end: "", expected: null },
      {
        precision: "year",
        label: "",
        start: "2017",
        end: "",
        expected: "2017-01-01T20:00:00.000Z",
      },
      {
        precision: "month",
        label: "",
        start: "2017-07",
        end: "",
        expected: "2017-07-01T19:00:00.000Z",
      },
      {
        precision: "day",
        label: "",
        start: "2017-07-08",
        end: "",
        expected: "2017-07-08T19:00:00.000Z",
      },
      {
        precision: "range",
        label: "",
        start: "2017-07-08",
        end: "2017-07-15",
        expected: "2017-07-08T19:00:00.000Z",
      },
      {
        precision: "exact",
        label: "",
        start: "2026-11-01T01:30",
        end: "",
        expected: "2026-11-01T08:30:00.000Z",
      },
    ];
    const goalParameters = {
      p_title: "Try skiing",
      p_body: "Keep the intention here",
      p_horizon: "someday",
      p_status: "active",
      p_target_date: null,
      p_collection_names: ["Bucket List"],
      p_tag_names: [],
      p_related_entry_ids: [],
      p_entry_id: null,
      p_expected_revision: null,
    };
    for (const value of cases) {
      const saved = await client.rpc("save_goal_entry", goalParameters);
      expect(saved.error).toBeNull();
      const id = saved.data[0].entry_id;
      await page.goto("/goals?entry=" + id);
      const dialog = page.getByRole("dialog");
      await dialog
        .getByRole("combobox", { name: "Date type", exact: true })
        .selectOption(value.precision);
      await expect(
        dialog.getByRole("combobox", { name: "Date type", exact: true }),
      ).toHaveValue(value.precision);
      await dialog
        .getByRole("combobox", { name: "Time zone", exact: true })
        .selectOption("America/Los_Angeles");
      if (value.start) await fillOccurrenceStart(dialog, value.start);
      if (value.end) await fillOccurrenceEnd(dialog, value.end);
      await dialog
        .getByRole("textbox", { name: /Human date label|Date description/ })
        .fill(value.label);
      await expect(
        dialog.getByRole("combobox", { name: "Date type", exact: true }),
      ).toHaveValue(value.precision);
      await expect(
        dialog.getByRole("textbox", { name: "Title", exact: true }),
      ).toHaveValue("Try skiing");
      if (value.precision === "age") {
        await page.screenshot({
          path: "/private/tmp/memotrail-goal-achievement-light.png",
        });
        await page.setViewportSize({ width: 390, height: 844 });
        await page.emulateMedia({ colorScheme: "dark" });
        await dialog
          .getByRole("button", {
            name: "Mark achieved and create First Time",
            exact: true,
          })
          .scrollIntoViewIfNeeded();
        await page.screenshot({
          path: "/private/tmp/memotrail-goal-achievement-mobile.png",
        });
        await page.setViewportSize({ width: 1280, height: 900 });
        await page.emulateMedia({ colorScheme: "light" });
      }
      await dialog
        .getByRole("button", {
          name: "Mark achieved and create First Time",
          exact: true,
        })
        .click();
      await expect(
        dialog.getByRole("button", {
          name: "Mark achieved and create First Time",
          exact: true,
        }),
      ).not.toBeVisible();
      const achievementLink = (
        await client
          .from("entry_links")
          .select("target_entry_id")
          .eq("source_entry_id", id)
          .eq("relationship", "achievement")
          .single()
      ).data!;
      const entry = (
        await client
          .from("entries")
          .select(
            "occurred_start,occurred_end,date_precision,occurred_label,body",
          )
          .eq("id", achievementLink.target_entry_id)
          .single()
      ).data!;
      expect(
        entry.occurred_start
          ? new Date(entry.occurred_start).toISOString()
          : null,
      ).toBe(value.expected);
      expect(
        entry.occurred_end ? new Date(entry.occurred_end).toISOString() : null,
      ).toBe(value.end ? "2017-07-15T19:00:00.000Z" : null);
      expect(entry.date_precision).toBe(value.precision);
      expect(entry.occurred_label).toBe(value.label || null);
      expect(entry.body).toBe("");
      const goal = await client
        .from("entries")
        .select("body,goals(status)")
        .eq("id", id)
        .single();
      expect(goal.data?.body).toBe("Keep the intention here");
      expect(goal.data?.goals).toEqual([{ status: "achieved" }]);
    }
    const concurrentGoal = await client.rpc("save_goal_entry", goalParameters);
    expect(concurrentGoal.error).toBeNull();
    const concurrentId = concurrentGoal.data[0].entry_id;
    const achievementParameters = {
      p_goal_entry_id: concurrentId,
      p_expected_revision: 1,
      p_occurred_start: null,
      p_occurred_end: null,
      p_date_precision: "unknown",
      p_occurred_label: null,
      p_occurred_timezone: null,
    };
    const results = await Promise.all([
      client.rpc("achieve_goal_with_occurrence", achievementParameters),
      client.rpc("achieve_goal_with_occurrence", achievementParameters),
    ]);
    expect(results.map((result) => result.error)).toEqual([null, null]);
    expect(results.map((result) => result.data.length).sort()).toEqual([0, 1]);
    const links = await client
      .from("entry_links")
      .select("target_entry_id")
      .eq("source_entry_id", concurrentId)
      .eq("relationship", "achievement");
    expect(links.data).toHaveLength(1);
    expect(uiErrors).toEqual([]);
  } finally {
    await admin.auth.admin.deleteUser(owner);
  }
});
