import { randomUUID } from "node:crypto";
import {
  expectSeparatorsBetweenWords,
  expectUnclippedFocusRing,
} from "./helpers/separators";
import { expect, test } from "./helpers/workspace-test";

test("Timeline summary keeps its separators between facts on phones", async ({
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
        item_subtype: "entry",
        occurred_start: "2017-06-01T12:00:00Z",
        occurred_timezone: "America/Los_Angeles",
        date_precision: "day",
        is_first_time: true,
      })
    ).error,
  ).toBeNull();

  await page.setViewportSize({ width: 320, height: 720 });
  await page.goto("/timeline");
  // A production build streams the page into a hidden boundary before it moves
  // into the workspace, so read the copy that is actually shown.
  const summary = page.getByRole("main").getByLabel("Timeline summary");
  await expect(summary).toContainText("1 First Time");
  // The range ends a little past today, so its last year depends on the date.
  await expect(summary).toContainText(/2017 to \d{4}/);
  await expect(
    summary.getByRole("button", { name: "Set birth date" }),
  ).toBeVisible();

  for (const width of [320, 390]) {
    await page.setViewportSize({ width, height: 720 });
    await expectSeparatorsBetweenWords(summary);
    // The clip that hides a line's leading separator leaves its focus ring whole.
    await expectUnclippedFocusRing(
      summary.getByRole("button", { name: "Set birth date" }),
    );
    await summary.screenshot({
      path: test.info().outputPath(`memotrail-timeline-summary-${width}.png`),
    });
  }
  await page.setViewportSize({ width: 1280, height: 720 });
  await expectSeparatorsBetweenWords(summary, { lines: 1 });
});

test("Dot-separated rows across the workspace keep their separators between facts on phones", async ({
  page,
  workspace: { client, owner },
}) => {
  test.setTimeout(120_000);
  const entryId = randomUUID();
  expect(
    (
      await client.from("entries").insert({
        id: entryId,
        owner_id: owner,
        title: "Lantern festival by the river",
        body: "Paper lanterns drifting down the river.",
        item_kind: "entry",
        item_subtype: "entry",
        occurred_start: "2017-06-01T12:00:00Z",
        occurred_timezone: "America/New_York",
        date_precision: "day",
        is_first_time: true,
      })
    ).error,
  ).toBeNull();
  const pages: { path: string; rows: number }[] = [
    { path: "/timeline", rows: 1 },
    { path: "/library?q=lantern", rows: 1 },
    { path: "/first-times", rows: 1 },
  ];
  for (const { path, rows } of pages) {
    await page.setViewportSize({ width: 320, height: 720 });
    await page.goto(path);
    const lists = page.locator("[data-ui-separated-list]:visible");
    await expect(lists, path).toHaveCount(rows);
    for (const width of [320, 390]) {
      await page.setViewportSize({ width, height: 720 });
      for (const list of await lists.all()) {
        await expectSeparatorsBetweenWords(list);
        for (const control of await list.locator("a, button").all())
          await expectUnclippedFocusRing(control);
      }
    }
  }
});
