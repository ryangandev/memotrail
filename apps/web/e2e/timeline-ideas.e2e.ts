import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

test("six Timeline ideas use current records and switch from the sidebar", async ({
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
  const email = `timeline-ideas-${randomUUID()}@memotrail.local`;
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
            inbox_status: "organized",
            item_kind: "entry",
            item_subtype: "moment",
            occurred_start: "2012-08-10T12:00:00Z",
            occurred_timezone: "America/Los_Angeles",
            date_precision: "day",
          },
          {
            id: periodId,
            owner_id: owner,
            title: "University years",
            body: "Learning and finding my people.",
            inbox_status: "organized",
            item_kind: "entry",
            item_subtype: "period",
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
            inbox_status: "organized",
            item_kind: "entry",
            item_subtype: "moment",
            occurred_label: "Around my twenties",
            occurred_timezone: "America/Los_Angeles",
            date_precision: "approximate",
          },
        ])
      ).error,
    ).toBeNull();
    const track = (
      await client.from("timeline_tracks").select("id").limit(1).single()
    ).data;
    expect(track?.id).toBeTruthy();
    expect(
      (
        await client.from("timeline_items").insert([
          {
            entry_id: momentId,
            owner_id: owner,
            track_id: track!.id,
            timeline_kind: "event",
          },
          {
            entry_id: periodId,
            owner_id: owner,
            track_id: track!.id,
            timeline_kind: "stage",
          },
          {
            entry_id: unanchoredId,
            owner_id: owner,
            track_id: track!.id,
            timeline_kind: "event",
          },
        ])
      ).error,
    ).toBeNull();

    const ideas = [
      [
        "01 Vertical Spine",
        "The Vertical Spine",
        "/timeline/ideas/vertical-spine",
      ],
      ["03 Swimlane", "Swimlane Timeline", "/timeline/ideas/swimlane"],
      ["07 Sticky Year", "Sticky-Year Feed", "/timeline/ideas/sticky-year"],
      ["08 Chapters", "A Life in Chapters", "/timeline/ideas/chapters"],
      ["18 Minimal Index", "A Life, Typeset", "/timeline/ideas/minimal-index"],
      [
        "19 Precision Ruler",
        "Precision Ruler",
        "/timeline/ideas/precision-ruler",
      ],
    ] as const;
    await page.goto(ideas[0][2]);
    const sidebar = page.getByRole("complementary");
    for (const [label, heading, href] of ideas) {
      await sidebar.getByRole("link", { name: label, exact: true }).click();
      await expect(page).toHaveURL(href);
      await expect(
        page.getByRole("heading", { name: heading, exact: true }),
      ).toBeVisible();
      await expect(page.getByText("First concert").first()).toBeVisible();
      await expect(page.getByText("University years").first()).toBeVisible();
      await expect(page.getByText("Started sketching").first()).toBeVisible();
      if (href.endsWith("swimlane") || href.endsWith("precision-ruler")) {
        await expect
          .poll(() =>
            page
              .getByRole("region", {
                name: href.endsWith("swimlane")
                  ? "Timeline by track"
                  : "Zoomable timeline ruler",
              })
              .evaluate((element) => element.scrollLeft),
          )
          .toBeGreaterThan(0);
      }
      if (process.env.MEMOTRAIL_CAPTURE_TIMELINE_IDEAS === "1") {
        await page.screenshot({
          caret: "initial",
          path: `/tmp/memotrail-idea-${href.split("/").pop()}-desktop.png`,
        });
      }
    }
    await page.getByRole("slider", { name: "Zoom" }).press("ArrowRight");
    await expect(page.getByText("1.25×")).toBeVisible();

    await page.goto(ideas[0][2]);
    await page
      .getByRole("link", { name: /First concert/ })
      .first()
      .click();
    await expect(page).toHaveURL(new RegExp(`/timeline\\?entry=${momentId}`));
    await expect(
      page.getByRole("dialog", { name: "First concert" }),
    ).toBeVisible();
    await page.getByRole("button", { name: "Close Timeline editor" }).click();
    await expect(page).toHaveURL(ideas[0][2]);

    await page.getByRole("link", { name: "Add moment" }).click();
    await expect(page).toHaveURL(
      /\/timeline\?new=1&returnTo=%2Ftimeline%2Fideas%2Fvertical-spine/,
    );
    await expect(
      page.getByRole("dialog", { name: "What are you adding?" }),
    ).toBeVisible();
    await page.getByRole("button", { name: "Add Moment" }).click();
    await expect(page.getByRole("dialog")).toBeVisible();
    await page.getByRole("button", { name: "Close Timeline editor" }).click();
    await expect(page).toHaveURL(ideas[0][2]);

    await page.setViewportSize({ width: 390, height: 844 });
    for (const [, heading, href] of ideas) {
      await page.goto(href);
      await expect(
        page.getByRole("heading", { name: heading, exact: true }),
      ).toBeVisible();
      await expect(
        page.getByRole("navigation", { name: "Timeline design ideas" }),
      ).toBeVisible();
      expect(
        await page.evaluate(() => document.documentElement.scrollWidth),
      ).toBeLessThanOrEqual(391);
      if (process.env.MEMOTRAIL_CAPTURE_TIMELINE_IDEAS === "1") {
        await page.screenshot({
          caret: "initial",
          path: `/tmp/memotrail-idea-${href.split("/").pop()}-mobile.png`,
        });
      }
    }
    expect(errors).toEqual([]);
  } finally {
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
