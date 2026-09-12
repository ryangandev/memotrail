import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("Inbox preserves uncertain dates and edits calendar precision without inventing dates", async ({
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
        })
      ).error,
    ).toBeNull();
    await page.goto("/inbox");
    const card = page.locator("article").filter({
      has: page.getByRole("heading", { name: "A memory without a date" }),
    });
    await expect(card).toContainText("Date unknown");
    await card.getByRole("button", { name: "Review", exact: true }).click();
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
      ["month", "2017-07", "Jul 2017"],
      ["day", "2017-07-08", "Jul 8, 2017"],
    ]) {
      await card.getByRole("button", { name: "Review", exact: true }).click();
      await page
        .getByRole("combobox", { name: "Date precision", exact: true })
        .selectOption(precision);
      await page.getByLabel("Occurred", { exact: true }).fill(start);
      await page
        .getByLabel("Time zone", { exact: true })
        .fill("Asia/Kathmandu");
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
    await card.getByRole("button", { name: "Review", exact: true }).click();
    await page
      .getByRole("combobox", { name: "Date precision", exact: true })
      .selectOption("range");
    await page.getByLabel("Occurred", { exact: true }).fill("2020-01-01");
    await page
      .getByLabel("End date (optional)", { exact: true })
      .fill("2017-01-01");
    await page
      .getByRole("button", { name: "Save changes", exact: true })
      .click();
    await expect(
      page.getByText("The end date must be on or after the start date."),
    ).toBeVisible();
    await page
      .getByLabel("End date (optional)", { exact: true })
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

    // A deterministic provider-response fixture isolates editable date adoption
    // from provider availability and costs. Real provider generation is covered
    // by the separately opt-in AI acceptance suite.
    await page.route("**/api/ai/suggestions", (route) =>
      route.fulfill({
        json: {
          suggestion: {
            id: randomUUID(),
            entry_revision: 6,
            status: "proposed",
            suggestions: {
              title: null,
              entryType: null,
              collections: [],
              tags: [],
              dateText: "17岁，第一次去日本",
              rationale: "Only the age is known.",
              confidence: 0.9,
            },
          },
        },
      }),
    );
    await card.getByRole("button", { name: "Review", exact: true }).click();
    await page.getByRole("button", { name: "Use as approximate date" }).click();
    await expect(
      page.getByRole("combobox", { name: "Date precision", exact: true }),
    ).toHaveValue("approximate");
    await expect(page.getByLabel("Occurred", { exact: true })).toHaveValue("");
    await expect(
      page.getByLabel("Date description", { exact: true }),
    ).toHaveValue("17岁，第一次去日本");
    expect(
      (
        await client
          .from("entries")
          .select("date_precision")
          .eq("id", entryID)
          .single()
      ).data?.date_precision,
    ).toBe("range");
    await page
      .getByRole("combobox", { name: "Date precision", exact: true })
      .selectOption("age");
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page
      .getByRole("group", { name: "When it happened" })
      .scrollIntoViewIfNeeded();
    await page.screenshot({
      path: "/private/tmp/memotrail-occurrence-mobile.png",
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
    const age = await client
      .from("entries")
      .select(
        "date_precision,occurred_start,occurred_end,occurred_label,inbox_status",
      )
      .eq("id", entryID)
      .single();
    expect(age.data).toEqual({
      date_precision: "age",
      occurred_start: null,
      occurred_end: null,
      occurred_label: "17岁，第一次去日本",
      inbox_status: "unreviewed",
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
    await card.getByRole("button", { name: "Review", exact: true }).click();
    await expect(page.getByLabel("Occurred", { exact: true })).toHaveValue(
      "2026-11-01T01:30:27",
    );
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
