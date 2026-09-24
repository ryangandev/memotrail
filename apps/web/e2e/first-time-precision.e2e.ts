import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import {
  fillOccurrenceEnd,
  fillOccurrenceStart,
  setDateDescription,
} from "./helpers/occurrence";

test("Editing a First Time keeps its original date range", async ({
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
  const email = `first-time-precision-${randomUUID()}@memotrail.local`;
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
          inbox_status: "organized",
          item_kind: "entry",
          item_subtype: "first_time",
          occurred_start: start,
          occurred_end: end,
          occurred_timezone: "UTC",
          date_precision: "range",
        })
      ).error,
    ).toBeNull();
    await page.goto("/library");
    await page.getByRole("link", { name: /First trip to Japan/ }).click();
    await expect(page).toHaveURL(`/first-times?entry=${id}`);
    const dialog = page.getByRole("dialog");
    await expect(
      dialog.getByText("Add this item to a larger story or chapter."),
    ).toHaveCount(0);
    await expect(
      dialog.getByText("Add specific descriptors for filtering and discovery."),
    ).toHaveCount(0);
    await expect
      .poll(() =>
        dialog
          .getByLabel("Date type")
          .evaluate(
            (control) => getComputedStyle(control.closest("label")!).rowGap,
          ),
      )
      .toBe("4px");
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-first-time-precision-desktop.png",
    });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-first-time-precision-mobile.png",
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
    await expect(page).toHaveURL(/\/first-times$/);
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
      dialog.getByRole("combobox", { name: "Date type", exact: true }),
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
      { precision: "year", start: "2017", label: "", end: "" },
      { precision: "month", start: "2017-07", label: "", end: "" },
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
        .getByRole("combobox", { name: "Date type", exact: true })
        .selectOption(sample.precision);
      if (sample.start) await fillOccurrenceStart(dialog, sample.start);
      if (sample.end) await fillOccurrenceEnd(dialog, sample.end);
      await setDateDescription(dialog, sample.label);
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
    expect(uiErrors).toEqual([]);
  } finally {
    await admin.auth.admin.deleteUser(owner);
  }
});
