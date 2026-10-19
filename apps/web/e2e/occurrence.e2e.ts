import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import {
  expectOccurrencePrecision,
  fillOccurrenceEnd,
  fillOccurrenceStart,
  occurrenceField,
  occurrenceStartField,
  setDateDescription,
  setOccurrencePrecision,
} from "./helpers/occurrence";

test("Entry editing preserves uncertain dates and edits calendar precision without inventing dates", async ({
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
  const email = `occurrence-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  if (!created.data.user)
    throw new Error("Local occurrence fixture unavailable.");
  const ownerID = created.data.user.id,
    entryID = randomUUID();
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
    if (!link.data.properties) throw new Error("Local sign-in unavailable.");
    expect(
      (
        await client.auth.verifyOtp({
          type: "magiclink",
          token_hash: link.data.properties.hashed_token,
        })
      ).error,
    ).toBeNull();
    await context.addCookies(
      cookies.map((c) => ({
        ...c,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax" as const,
        httpOnly: false,
      })),
    );
    expect(
      (
        await client.from("entries").insert({
          id: entryID,
          owner_id: ownerID,
          title: "A memory without a date",
          body: "I remember the feeling, not the date.",
          date_precision: "unknown",
          occurred_start: null,
          occurred_timezone: "Asia/Kathmandu",
        })
      ).error,
    ).toBeNull();
    await page.goto(`/items/${entryID}`);
    const card = page.getByRole("article", { name: "Entry", exact: true });
    await expect(card).toContainText("Undated");
    await page.getByRole("button", { name: "Edit Entry", exact: true }).click();
    await page
      .getByRole("textbox", { name: "Note", exact: true })
      .fill("The feeling is still vivid.");
    await page
      .getByRole("button", { name: "Save changes", exact: true })
      .click();
    await expect(page.getByRole("dialog")).toHaveCount(0);
    const saved = await client
      .from("entries")
      .select(
        "date_precision,occurred_start,occurred_end,occurred_label,revision",
      )
      .eq("id", entryID)
      .single();
    expect(saved.data).toMatchObject({
      date_precision: "unknown",
      occurred_start: null,
      occurred_end: null,
      occurred_label: null,
      revision: 2,
    });
    for (const [precision, start, expected] of [
      ["year", "2017", "2017"],
      ["month", "2017-07", "July 2017"],
      ["day", "2017-07-08", "Saturday, July 8, 2017"],
    ] as const) {
      await page
        .getByRole("button", { name: "Edit Entry", exact: true })
        .click();
      await setOccurrencePrecision(page, precision);
      await fillOccurrenceStart(page, start);
      // A date without a time shows no time zone and keeps the recorded one.
      await expect(
        page.getByRole("combobox", { name: "Time zone", exact: true }),
      ).toHaveCount(0);
      await page
        .getByRole("button", { name: "Save changes", exact: true })
        .click();
      await expect(page.getByRole("dialog")).toHaveCount(0);
      await expect(card).toContainText(expected);
      const row = await client
        .from("entries")
        .select("date_precision,occurred_timezone")
        .eq("id", entryID)
        .single();
      expect(row.data).toEqual({
        date_precision: precision,
        occurred_timezone: "Asia/Kathmandu",
      });
    }
    // A time recorded outside the Settings time zone shows its zone in full.
    await page.getByRole("button", { name: "Edit Entry", exact: true }).click();
    await setOccurrencePrecision(page, "exact");
    await expect(
      page.getByRole("combobox", { name: "Time zone", exact: true }),
    ).toHaveValue("Asia/Kathmandu");
    await expect(
      page.getByText("Entry override", { exact: true }),
    ).toBeVisible();
    await page.getByRole("button", { name: "Cancel", exact: true }).click();
    await expect(page.getByRole("dialog")).toHaveCount(0);
    await page.getByRole("button", { name: "Edit Entry", exact: true }).click();
    await setOccurrencePrecision(page, "range");
    await fillOccurrenceStart(page, "2020-01-01");
    await fillOccurrenceEnd(page, "2017-01-01");
    await page
      .getByRole("button", { name: "Save changes", exact: true })
      .click();
    await expect(
      page.getByText("The end date must be on or after the start date."),
    ).toBeVisible();
    await page
      .getByRole("textbox", { name: "End date", exact: true })
      .fill("2023-01-01");
    await page
      .getByRole("button", { name: "Save changes", exact: true })
      .click();
    await expect(page.getByRole("dialog")).toHaveCount(0);
    const range = await client
      .from("entries")
      .select("date_precision,occurred_end")
      .eq("id", entryID)
      .single();
    expect(range.data?.date_precision).toBe("range");
    expect(range.data?.occurred_end).not.toBeNull();

    await page.getByRole("button", { name: "Edit Entry", exact: true }).click();
    await setOccurrencePrecision(page, "approximate");
    await expect(occurrenceStartField(page)).toHaveValue("2020-01-01");
    await expect(
      page.getByRole("textbox", { name: "End date", exact: true }),
    ).toHaveValue("2023-01-01");
    await page
      .getByRole("checkbox", { name: "Add end date", exact: true })
      .uncheck();
    await occurrenceStartField(page).fill("");
    await setDateDescription(page, "17岁，第一次去日本");
    expect(
      (
        await client
          .from("entries")
          .select("date_precision")
          .eq("id", entryID)
          .single()
      ).data?.date_precision,
    ).toBe("range");
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await occurrenceField(page).scrollIntoViewIfNeeded();
    await page.screenshot({
      animations: "disabled",
      path: test.info().outputPath("memotrail-occurrence-mobile.png"),
      fullPage: true,
      caret: "initial",
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await page
      .getByRole("button", { name: "Save changes", exact: true })
      .click();
    await expect(page.getByRole("dialog")).toHaveCount(0);
    const approximate = await client
      .from("entries")
      .select("date_precision,occurred_start,occurred_end,occurred_label")
      .eq("id", entryID)
      .single();
    expect(approximate.data).toEqual({
      date_precision: "approximate",
      occurred_start: null,
      occurred_end: null,
      occurred_label: "17岁，第一次去日本",
    });

    // An age recorded before Not sure existed stays an age through an edit.
    expect(
      (
        await client
          .from("entries")
          .update({ date_precision: "age" })
          .eq("id", entryID)
      ).error,
    ).toBeNull();
    await page.reload();
    await page.getByRole("button", { name: "Edit Entry", exact: true }).click();
    await expectOccurrencePrecision(page, "age");
    await page
      .getByRole("textbox", { name: "Note", exact: true })
      .fill("Still an age.");
    await page
      .getByRole("button", { name: "Save changes", exact: true })
      .click();
    await expect(page.getByRole("dialog")).toHaveCount(0);
    expect(
      (
        await client
          .from("entries")
          .select("date_precision,occurred_label")
          .eq("id", entryID)
          .single()
      ).data,
    ).toEqual({
      date_precision: "age",
      occurred_label: "17岁，第一次去日本",
    });

    expect(
      (
        await client
          .from("entries")
          .update({
            date_precision: "exact",
            occurred_start: "2026-11-01T09:30:27.123Z",
            occurred_label: null,
            occurred_timezone: "America/Los_Angeles",
          })
          .eq("id", entryID)
      ).error,
    ).toBeNull();
    await page.reload();
    await page.getByRole("button", { name: "Edit Entry", exact: true }).click();
    await expect(occurrenceStartField(page)).toHaveValue("2026-11-01");
    await expect(
      page.getByRole("button", {
        name: "Choose occurred time",
        exact: true,
      }),
    ).toContainText("01:30");
    await page
      .getByRole("textbox", { name: "Note", exact: true })
      .fill("Only this note changed.");
    await page
      .getByRole("button", { name: "Save changes", exact: true })
      .click();
    await expect(page.getByRole("dialog")).toHaveCount(0);
    const exact = await client
      .from("entries")
      .select("occurred_start,occurred_timezone,date_precision")
      .eq("id", entryID)
      .single();
    expect(exact.data).toMatchObject({
      occurred_timezone: "America/Los_Angeles",
      date_precision: "exact",
    });
    expect(Date.parse(exact.data!.occurred_start)).toBe(
      Date.parse("2026-11-01T09:30:27.123Z"),
    );
  } finally {
    expect((await admin.auth.admin.deleteUser(ownerID)).error).toBeNull();
  }
});
