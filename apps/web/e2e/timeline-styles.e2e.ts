import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

test("Timeline style setting changes the real Timeline without changing its records", async ({
  context,
  page,
}) => {
  test.setTimeout(120_000);
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  const local = JSON.parse(
    execFileSync("supabase", ["status", "-o", "json"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }),
  );
  expect(local.API_URL).toBe("http://127.0.0.1:54321");
  const admin = createClient(local.API_URL, local.SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
  const email = `timeline-styles-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  expect(created.error).toBeNull();
  const owner = created.data.user!.id;

  try {
    const cookies: { name: string; value: string }[] = [];
    const client = createServerClient(local.API_URL, local.ANON_KEY, {
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
    expect(link.error).toBeNull();
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

    expect(
      (
        await client
          .from("profiles")
          .update({ birth_date: "1990-03-14", timezone: "America/Los_Angeles" })
          .eq("user_id", owner)
      ).error,
    ).toBeNull();
    const momentId = randomUUID();
    const periodId = randomUUID();
    const unanchoredId = randomUUID();
    expect(
      (
        await client.from("entries").insert([
          {
            id: momentId,
            owner_id: owner,
            title: "First concert",
            body: "A night I still remember.",
            item_kind: "entry",
            item_subtype: "entry",
            occurred_start: "2012-08-10T12:00:00Z",
            occurred_timezone: "America/Los_Angeles",
            date_precision: "day",
          },
          {
            id: periodId,
            owner_id: owner,
            title: "University years",
            body: "Learning and finding my people.",
            item_kind: "entry",
            item_subtype: "entry",
            occurred_start: "2008-09-01T12:00:00Z",
            occurred_end: "2012-06-01T12:00:00Z",
            occurred_timezone: "America/Los_Angeles",
            date_precision: "range",
          },
          {
            id: unanchoredId,
            owner_id: owner,
            title: "Started sketching",
            body: "A quiet new habit.",
            item_kind: "entry",
            item_subtype: "entry",
            occurred_label: "Around my twenties",
            occurred_timezone: "America/Los_Angeles",
            date_precision: "approximate",
          },
        ])
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("milestones").insert([
          {
            entry_id: momentId,
            owner_id: owner,
            shape: "moment",
            lane: "other",
          },
          {
            entry_id: periodId,
            owner_id: owner,
            shape: "period",
            lane: "work_study",
          },
          {
            entry_id: unanchoredId,
            owner_id: owner,
            shape: "moment",
            lane: "other",
          },
        ])
      ).error,
    ).toBeNull();

    async function expectStyleCookie(style: string) {
      await expect
        .poll(async () =>
          decodeURIComponent(
            (await context.cookies()).find(
              (cookie) => cookie.name === "memotrail-timeline-style",
            )?.value ?? "",
          ),
        )
        .toBe(`${owner}:${style}`);
    }

    await page.goto("/timeline");
    await expect(
      page.getByRole("region", { name: "Timeline by lane" }).first(),
    ).toBeVisible();
    await expect(
      page.getByRole("region", { name: "Vertical timeline" }),
    ).toHaveCount(0);

    await page.goto("/settings");
    await expect(page.getByRole("radio", { name: "Classic" })).toBeChecked();
    if (process.env.MEMOTRAIL_CAPTURE_TIMELINE_STYLES === "1") {
      await page.screenshot({
        caret: "initial",
        fullPage: true,
        path: "/tmp/memotrail-timeline-setting-desktop.png",
      });
    }
    await page.getByRole("radio", { name: "Vertical Spine" }).check();
    await expect(
      page.getByRole("radio", { name: "Vertical Spine" }),
    ).toBeChecked();
    await expectStyleCookie("vertical");
    await page.goto("/timeline");
    await expect(
      page.getByRole("region", { name: "Vertical timeline" }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: /First concert/ }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: /University years/ }),
    ).toBeVisible();
    await expect(
      page.getByRole("heading", { name: "Without a calendar date" }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: /Started sketching/ }),
    ).toBeVisible();
    await page.reload();
    await expect(
      page.getByRole("region", { name: "Vertical timeline" }),
    ).toBeVisible();
    if (process.env.MEMOTRAIL_CAPTURE_TIMELINE_STYLES === "1") {
      await page.screenshot({
        caret: "initial",
        path: "/tmp/memotrail-timeline-vertical-desktop.png",
      });
    }
    await page.getByRole("link", { name: /First concert/ }).click();
    await expect(page).toHaveURL(`/items/${momentId}`);
    await page.goBack();
    await expect(
      page.getByRole("region", { name: "Vertical timeline" }),
    ).toBeVisible();

    await page.goto("/settings");
    await page.getByRole("radio", { name: "Sticky Year" }).check();
    await expectStyleCookie("sticky-year");
    await page.goto("/timeline");
    await expect(
      page.getByRole("region", { name: "Timeline by year" }),
    ).toBeVisible();
    await expect(page.getByRole("heading", { name: "2008" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "2012" })).toBeVisible();
    await expect(
      page.getByRole("link", { name: /Started sketching/ }),
    ).toBeVisible();
    if (process.env.MEMOTRAIL_CAPTURE_TIMELINE_STYLES === "1") {
      await page.screenshot({
        caret: "initial",
        path: "/tmp/memotrail-timeline-sticky-year-desktop.png",
      });
    }
    await expect(
      page.getByRole("link", { name: /University years, .*Work and study/ }),
    ).toContainText("Period");
    await page.getByRole("link", { name: /University years/ }).click();
    await expect(page).toHaveURL(`/items/${periodId}`);

    await page.setViewportSize({ width: 390, height: 844 });
    for (const [style, label] of [
      ["sticky-year", "Sticky Year"],
      ["vertical", "Vertical Spine"],
    ] as const) {
      await page.goto("/settings");
      expect(
        await page.evaluate(() => document.documentElement.scrollWidth),
      ).toBeLessThanOrEqual(391);
      if (
        style === "sticky-year" &&
        process.env.MEMOTRAIL_CAPTURE_TIMELINE_STYLES === "1"
      ) {
        await page.screenshot({
          caret: "initial",
          fullPage: true,
          path: "/tmp/memotrail-timeline-setting-mobile.png",
        });
      }
      await page.getByRole("radio", { name: label }).check();
      await expectStyleCookie(style);
      await page.goto("/timeline");
      await expect(
        page.getByRole("region", {
          name: style === "vertical" ? "Vertical timeline" : "Timeline by year",
        }),
      ).toBeVisible();
      expect(
        await page.evaluate(() => document.documentElement.scrollWidth),
      ).toBeLessThanOrEqual(391);
      if (process.env.MEMOTRAIL_CAPTURE_TIMELINE_STYLES === "1") {
        await page.screenshot({
          caret: "initial",
          path: `/tmp/memotrail-timeline-${style}-mobile.png`,
        });
      }
    }

    await page.goto("/settings");
    await page.getByRole("radio", { name: "Classic" }).check();
    await expectStyleCookie("classic");
    await page.goto("/timeline");
    await expect(
      page.getByRole("region", { name: "Timeline by lane" }).first(),
    ).toBeVisible();
    await expect(
      page.getByRole("region", { name: "Vertical timeline" }),
    ).toHaveCount(0);
    await page.getByRole("button", { name: "Add to Timeline" }).click();
    await expect(
      page.getByRole("dialog", { name: "What are you adding?" }),
    ).toBeVisible();
    await page.getByRole("button", { name: "Close Timeline chooser" }).click();
    expect(errors).toEqual([]);
  } finally {
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
