import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import {
  fillOccurrenceEnd,
  fillOccurrenceStart,
} from "./helpers/occurrence";

test("Timeline edits preserve full occurrence precision without fabricated dates", async ({
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
  const email = `timeline-precision-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  const owner = created.data.user!.id,
    id = randomUUID();
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
    const start = "2017-07-08T12:00:00+00:00",
      end = "2017-07-15T12:00:00+00:00";
    expect(
      (
        await client.from("entries").insert({
          id,
          owner_id: owner,
          title: "First trip to Japan",
          body: "Original travel memory",
          entry_type: "life_stage",
          occurred_start: start,
          occurred_end: end,
          occurred_timezone: "UTC",
          date_precision: "range",
        })
      ).error,
    ).toBeNull();
    const track = (
      await client
        .from("timeline_tracks")
        .select("id")
        .eq("system_key", "life_stages")
        .single()
    ).data;
    const fallbackTrack =
      track ??
      (await client.from("timeline_tracks").select("id").limit(1).single())
        .data;
    expect(
      (
        await client.from("timeline_items").insert({
          entry_id: id,
          track_id: fallbackTrack!.id,
          owner_id: owner,
          timeline_kind: "stage",
        })
      ).error,
    ).toBeNull();
    await page.goto("/timeline");
    await page.getByRole("button", { name: /First trip to Japan/ }).click();
    const dialog = page.getByRole("dialog");
    await page.screenshot({
      path: "/private/tmp/memotrail-timeline-precision-desktop.png",
    });
    const startDatePicker = dialog.getByRole("button", {
      name: "Choose start date",
      exact: true,
    });
    await startDatePicker.click();
    await expect(
      page.locator(
        '[data-scope="date-picker"][data-part="content"][data-state="open"]',
      ),
    ).toBeVisible();
    await page.screenshot({
      path: "/private/tmp/memotrail-date-picker-desktop.png",
    });
    await startDatePicker.click();
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.screenshot({
      path: "/private/tmp/memotrail-timeline-precision-mobile.png",
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);
    await page.setViewportSize({ width: 1280, height: 720 });
    await page.emulateMedia({ colorScheme: "light" });
    await dialog.getByRole("button", { name: "Save changes" }).click();
    await expect(dialog).not.toBeVisible();
    await expect
      .poll(
        async () =>
          (
            await client
              .from("entries")
              .select("revision")
              .eq("id", id)
              .single()
          ).data?.revision,
      )
      .toBeGreaterThan(1);
    const saved = (
      await client
        .from("entries")
        .select("occurred_start,occurred_end,date_precision")
        .eq("id", id)
        .single()
    ).data!;
    expect(saved.occurred_end).toBe(end);
    expect(saved.occurred_start).toBe(start);
    expect(saved.date_precision).toBe("range");
    // Untouched fractional instants and the second repeated DST hour must survive.
    const revision = (
      await client.from("entries").select("revision").eq("id", id).single()
    ).data!.revision;
    const exact = "2026-11-01T09:30:00.123456+00:00";
    expect(
      (
        await client
          .from("entries")
          .update({
            occurred_start: exact,
            occurred_end: null,
            date_precision: "exact",
            occurred_timezone: "America/Los_Angeles",
            revision: revision + 1,
          })
          .eq("id", id)
      ).error,
    ).toBeNull();
    await page.reload();
    await page.getByRole("button", { name: /First trip to Japan/ }).click();
    await expect(
      dialog.getByRole("combobox", { name: "Date precision", exact: true }),
    ).toHaveValue("exact");
    await dialog.getByRole("button", { name: "Save changes" }).click();
    await expect(dialog).not.toBeVisible();
    expect(
      (
        await client
          .from("entries")
          .select("occurred_start")
          .eq("id", id)
          .single()
      ).data!.occurred_start,
    ).toBe(exact);
    for (const sample of [
      { precision: "year", start: "2017", label: "", end: "2023" },
      { precision: "month", start: "2017-07", label: "", end: "2023-06" },
      { precision: "day", start: "2017-07-08", label: "", end: "" },
      { precision: "age", start: "", label: "17岁", end: "" },
      {
        precision: "approximate",
        start: "",
        label: "Summer before college",
        end: "",
      },
      { precision: "range", start: "2017-07-08", label: "", end: "2017-07-15" },
      { precision: "unknown", start: "", label: "", end: "" },
    ]) {
      await page.getByRole("button", { name: /First trip to Japan/ }).click();
      await dialog
        .getByRole("combobox", { name: "Date precision", exact: true })
        .selectOption(sample.precision);
      if (sample.start)
        await fillOccurrenceStart(dialog, sample.start);
      if (sample.end)
        await fillOccurrenceEnd(dialog, sample.end);
      await dialog.getByLabel("Date description").fill(sample.label);
      await dialog.getByRole("button", { name: "Save changes" }).click();
      await expect(dialog).not.toBeVisible();
      const value = (
        await client
          .from("entries")
          .select("date_precision,occurred_start,occurred_end,occurred_label")
          .eq("id", id)
          .single()
      ).data!;
      expect(value.date_precision).toBe(sample.precision);
      if (!sample.start) expect(value.occurred_start).toBeNull();
      if (sample.end) expect(value.occurred_end).not.toBeNull();
    }
    await expect(
      page.getByRole("region", { name: "Without a calendar date" }),
    ).toContainText("First trip to Japan");
    await page.screenshot({
      path: "/private/tmp/memotrail-timeline-undated.png",
    });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.getByRole("button", { name: /First trip to Japan/ }).click();
    await expect(dialog.getByLabel("Date precision")).toHaveValue("unknown");
    await dialog.getByRole("button", { name: "Cancel", exact: true }).click();
    await page.getByRole("button", { name: "Add moment", exact: true }).click();
    await expect(dialog.getByLabel("Date precision")).toHaveValue("unknown");
    await dialog.getByRole("button", { name: "Event", exact: true }).click();
    await expect(
      dialog
        .getByRole("combobox", { name: "Date precision", exact: true })
        .locator('option[value="range"]'),
    ).toHaveCount(0);
    await dialog.getByRole("button", { name: "Stage", exact: true }).click();
    await dialog.getByLabel("Date precision").selectOption("range");
    await expect(
      dialog.getByRole("checkbox", { name: "Present", exact: true }),
    ).toBeChecked();
    await expect(dialog.getByText("Ongoing through present")).toBeVisible();
    await dialog
      .getByLabel("Title", { exact: true })
      .fill("Unanchored childhood");
    await dialog.getByLabel("Date precision").selectOption("age");
    await dialog.getByLabel("Date description").fill("Ages 1 to 12");
    await dialog
      .getByRole("button", { name: "Add moment", exact: true })
      .click();
    await expect(dialog).not.toBeVisible();
    const createdMoment = await client
      .from("entries")
      .select("occurred_start,date_precision")
      .eq("title", "Unanchored childhood")
      .single();
    expect(createdMoment.data).toMatchObject({
      occurred_start: null,
      date_precision: "age",
    });
    expect(uiErrors).toEqual([]);
  } finally {
    await admin.auth.admin.deleteUser(owner);
  }
});
