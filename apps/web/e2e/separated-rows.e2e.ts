import { randomUUID } from "node:crypto";
import {
  expectSeparatorsBetweenWords,
  expectUnclippedFocusRing,
} from "./helpers/separators";
import { expect, test } from "./helpers/workspace-test";

test("Timeline summary keeps its separators between facts as it wraps", async ({
  page,
  workspace: { client, owner },
}) => {
  const momentId = randomUUID();
  expect(
    (
      await client.from("entries").insert({
        id: momentId,
        owner_id: owner,
        title: "Moved across the country",
        item_kind: "entry",
        item_subtype: "moment",
        occurred_start: "2017-06-01T12:00:00Z",
        occurred_timezone: "America/Los_Angeles",
        date_precision: "day",
      })
    ).error,
  ).toBeNull();
  const track = (
    await client.from("timeline_tracks").select("id").limit(1).single()
  ).data;
  expect(
    (
      await client.from("timeline_items").insert({
        entry_id: momentId,
        owner_id: owner,
        track_id: track!.id,
        timeline_kind: "event",
      })
    ).error,
  ).toBeNull();

  await page.setViewportSize({ width: 320, height: 720 });
  await page.goto("/timeline");
  // The account has no birth date yet, so the prompt opens first.
  await page
    .getByRole("dialog", { name: "When did your story begin?" })
    .getByRole("button", { name: "Not now", exact: true })
    .click();
  const summary = page.getByLabel("Timeline summary");
  await expect(summary).toContainText("1 moment");
  await expect(
    summary.getByRole("button", { name: "Set birth date" }),
  ).toBeVisible();

  for (const width of [320, 390]) {
    await page.setViewportSize({ width, height: 720 });
    const lines = await expectSeparatorsBetweenWords(summary);
    expect(lines.length, JSON.stringify(lines)).toBeGreaterThan(1);
    // The clip that hides a line's leading separator leaves its focus ring whole.
    await expectUnclippedFocusRing(
      summary.getByRole("link", { name: "Manage tracks" }),
    );
    await summary.screenshot({
      path: `/private/tmp/memotrail-timeline-summary-${width}.png`,
    });
  }
  await page.setViewportSize({ width: 1280, height: 720 });
  await expectSeparatorsBetweenWords(summary, { lines: 1 });
});

test("Dot-separated rows across the workspace keep their separators between facts on phones", async ({
  context,
  page,
  workspace: { client, owner },
}) => {
  test.setTimeout(120_000);
  const entryId = randomUUID();
  const locationId = randomUUID();
  expect(
    (
      await client.from("entries").insert({
        id: entryId,
        owner_id: owner,
        title: "Lantern festival by the river",
        body: "Paper lanterns drifting down the river.",
        item_kind: "entry",
        item_subtype: "moment",
        occurred_start: "2017-06-01T12:00:00Z",
        occurred_timezone: "America/New_York",
        date_precision: "day",
      })
    ).error,
  ).toBeNull();
  const track = (
    await client.from("timeline_tracks").select("id").limit(1).single()
  ).data;
  expect(
    (
      await client
        .from("timeline_tracks")
        .update({ name: "Neighborhood friendships and community life" })
        .eq("id", track!.id)
    ).error,
  ).toBeNull();
  expect(
    (
      await client.from("timeline_items").insert({
        entry_id: entryId,
        owner_id: owner,
        track_id: track!.id,
        timeline_kind: "event",
      })
    ).error,
  ).toBeNull();
  expect(
    (
      await client.from("locations").insert({
        id: locationId,
        owner_id: owner,
        bound_entry_id: entryId,
        formatted_address:
          "1200 Riverside Drive, Upper West Side, New York, NY 10027",
        address: "1200 Riverside Drive",
        city: "New York",
        latitude: 40.8135,
        longitude: -73.9622,
      })
    ).error,
  ).toBeNull();
  expect(
    (
      await client.from("entry_locations").insert({
        owner_id: owner,
        entry_id: entryId,
        location_id: locationId,
        relationship: "primary",
      })
    ).error,
  ).toBeNull();
  await context.addCookies([
    {
      name: "memotrail-timeline-style",
      value: `${owner}:sticky-year`,
      domain: "127.0.0.1",
      path: "/",
      sameSite: "Lax",
    },
  ]);

  const pages: {
    path: string;
    open?: () => Promise<void>;
    rows: number;
    wrapping?: string;
  }[] = [
    {
      path: "/timeline",
      open: () =>
        page
          .getByRole("dialog", { name: "When did your story begin?" })
          .getByRole("button", { name: "Not now", exact: true })
          .click(),
      rows: 2,
      wrapping: "Neighborhood friendships and community life",
    },
    {
      path: "/map",
      open: () => page.locator(".leaflet-marker-icon").click(),
      rows: 2,
      wrapping: "1200 Riverside Drive, Upper West Side, New York, NY 10027",
    },
    { path: "/library?q=lantern", rows: 1 },
    { path: "/homes", rows: 1 },
    { path: "/vehicles", rows: 1 },
    { path: "/goals", rows: 1 },
    { path: "/first-times", rows: 1 },
  ];
  for (const { path, open, rows, wrapping } of pages) {
    await page.setViewportSize({ width: 320, height: 720 });
    await page.goto(path);
    await open?.();
    const lists = page.locator("[data-ui-separated-list]:visible");
    await expect(lists, path).toHaveCount(rows);
    for (const width of [320, 390]) {
      await page.setViewportSize({ width, height: 720 });
      for (const list of await lists.all()) {
        const lines = await expectSeparatorsBetweenWords(list);
        if (
          width === 320 &&
          wrapping &&
          (await list.textContent())?.includes(wrapping)
        )
          expect(
            lines.length,
            `${path}: ${JSON.stringify(lines)}`,
          ).toBeGreaterThan(1);
        for (const control of await list.locator("a, button").all())
          await expectUnclippedFocusRing(control);
      }
    }
  }
});
