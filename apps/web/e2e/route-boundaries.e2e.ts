import { randomUUID } from "node:crypto";
import type { Page } from "@playwright/test";
import { expect, test } from "./helpers/workspace-test";

/** The sidebar link marked as the current destination, or none. */
function currentDestination(page: Page) {
  return page.getByRole("complementary").locator('nav a[aria-current="page"]');
}

test("An unknown page keeps the workspace and offers the way back", async ({
  page,
  workspace,
}) => {
  void workspace;
  const response = await page.goto("/no-such-page");

  expect(response?.status()).toBe(404);
  await expect(
    page.getByRole("heading", { name: "Page not found" }),
  ).toBeVisible();
  // The sidebar stays, so there is always somewhere to go next, but no destination is current.
  await expect(
    page.getByRole("navigation", { name: "Primary navigation" }),
  ).toBeVisible();
  await expect(currentDestination(page)).toHaveCount(0);
  await page.screenshot({
    animations: "disabled",
    caret: "initial",
    path: test.info().outputPath("memotrail-not-found.png"),
  });

  await page
    .getByRole("main")
    .getByRole("link", { name: "Go to Dashboard" })
    .click();
  await expect(page).toHaveURL(/\/$/);
  await expect(currentDestination(page)).toHaveText("Dashboard");
});

test("An Entry page belongs to the destination its Entry does", async ({
  page,
  workspace: { client, owner },
}) => {
  const entry = (fields: { title: string } & Record<string, unknown>) => ({
    id: randomUUID(),
    owner_id: owner,
    body: "",
    item_kind: "entry",
    item_subtype: "entry",
    occurred_start: "2026-05-01T12:00:00+00:00",
    occurred_timezone: "UTC",
    date_precision: "day",
    is_first_time: false,
    ...fields,
  });
  const ordinary = entry({ title: "Quiet morning walk" });
  const chapter = entry({ title: "Studying abroad", item_subtype: "chapter" });
  const firstTime = entry({ title: "First marathon", is_first_time: true });
  const trashed = entry({
    title: "Old shopping note",
    deleted_at: new Date().toISOString(),
  });
  expect(
    (
      await client
        .from("entries")
        .insert([ordinary, chapter, firstTime, trashed])
    ).error,
  ).toBeNull();

  for (const [row, destination, href] of [
    [ordinary, "Library", "/library"],
    [chapter, "Timeline", "/timeline"],
    [firstTime, "First Times", "/first-times"],
    [trashed, "Trash", "/trash"],
  ] as const) {
    await page.goto(`/items/${row.id}`);
    await expect(
      page.getByRole("heading", { level: 1, name: row.title }),
    ).toBeVisible();
    await expect(currentDestination(page)).toHaveText(destination);
    const back = page.locator("[data-page-back]");
    await expect(back).toHaveText(destination);
    await expect(back).toHaveAttribute("href", href);
  }

  // A missing Entry shares the not-found layout and belongs to no destination.
  await page.goto(`/items/${randomUUID()}`);
  const fallback = page.locator("[data-route-fallback]");
  await expect(
    fallback.getByRole("heading", { level: 1, name: "Entry unavailable" }),
  ).toBeVisible();
  await expect(
    fallback.getByText("It may have moved to Trash, or it no longer exists."),
  ).toBeVisible();
  await expect(fallback.getByRole("link")).toHaveText([
    "Open Library",
    "Open Trash",
  ]);
  await expect(currentDestination(page)).toHaveCount(0);

  await page.goto("/no-such-page");
  await expect(page.locator("[data-route-fallback]")).toBeVisible();

  // A year review belongs to Reviews and links back to it.
  await page.goto("/reviews/2025");
  await expect(currentDestination(page)).toHaveText("Reviews");
  await expect(page.locator("[data-page-back]")).toHaveText("Reviews");
});
