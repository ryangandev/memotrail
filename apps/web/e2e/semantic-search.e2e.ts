import { randomUUID } from "node:crypto";
import type { Page } from "@playwright/test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { test, expect } from "./helpers/workspace-test";
import { SEMANTIC_MODEL } from "../src/lib/search/semantic-config";

// Any query containing this phrase makes the fake embedding service answer 503, like an
// outage (scripts/fake-embedding-server.mjs).
const OUTAGE_SENTINEL = "SEMANTIC_OUTAGE_SENTINEL";

// This suite runs only through playwright.semantic.config.ts, which starts the
// deterministic fake embedding service beside the app. The fake puts texts that share a
// synonym group close together, so the Entries below match by meaning without sharing a
// single word with the descriptions that find them.

type Seed = {
  body: string;
  date?: { start: string; end?: string; precision: string };
  subtype?: string;
  tag?: string;
  title: string;
};

async function seed(
  client: SupabaseClient,
  owner: string,
  entries: Seed[],
): Promise<Map<string, string>> {
  const ids = new Map<string, string>();
  for (const entry of entries) {
    const id = randomUUID();
    ids.set(entry.title, id);
    expect(
      (
        await client.from("entries").insert({
          body: entry.body,
          date_precision: entry.date?.precision ?? "unknown",
          id,
          item_kind: "entry",
          item_subtype: entry.subtype ?? "entry",
          occurred_end: entry.date?.end ?? null,
          occurred_start: entry.date?.start ?? null,
          occurred_timezone: entry.date ? "UTC" : null,
          owner_id: owner,
          title: entry.title,
        })
      ).error,
    ).toBeNull();
    if (entry.tag) {
      const tagId = randomUUID();
      expect(
        (
          await client
            .from("tags")
            .insert({ id: tagId, name: entry.tag, owner_id: owner })
        ).error,
      ).toBeNull();
      expect(
        (
          await client
            .from("entry_tags")
            .insert({ entry_id: id, owner_id: owner, tag_id: tagId })
        ).error,
      ).toBeNull();
    }
  }
  return ids;
}

/** Every search the page makes schedules a drain, so visiting it indexes the Entries. */
async function waitUntilIndexed(page: Page, client: SupabaseClient) {
  await expect
    .poll(
      async () => {
        await page.goto("/search?q=" + encodeURIComponent("warm up"));
        const status = await client.rpc("search_index_status", {
          p_model: SEMANTIC_MODEL,
        });
        return status.data?.[0]?.pending ?? -1;
      },
      { intervals: [500, 1000, 2000], timeout: 45_000 },
    )
    .toBe(0);
}

// A Chapter's row is named with its mark, such as "Chapter Riding years", so names match in part.
function resultCard(page: Page, title: string) {
  return page.locator("[data-ui-entry-row]").filter({
    has: page.getByRole("link", { name: title }),
  });
}

function resultTitles(page: Page) {
  return page
    .locator("[data-ui-entry-row] [data-entry-row-title]")
    .allTextContents();
}

const friend: Seed = {
  body: "Chatted with a friendly man while he tuned my commuter.",
  date: { precision: "month", start: "2026-05-10T12:00:00Z" },
  tag: "Neighbors",
  title: "Saturday afternoon",
};
const unrelated: Seed[] = [
  {
    body: "Tomatoes and basil for the caprese salad at the farmers market.",
    title: "Sunday groceries",
  },
  {
    body: "Repotted the fern on the balcony.",
    title: "Plants",
  },
];

test("A description finds an Entry that shares no words with it", async ({
  page,
  workspace,
}) => {
  const ids = await seed(workspace.client, workspace.owner, [
    friend,
    ...unrelated,
  ]);
  await waitUntilIndexed(page, workspace.client);

  await page.goto(
    "/search?q=" + encodeURIComponent("the mechanic who repairs bicycles"),
  );
  const card = resultCard(page, "Saturday afternoon");
  await expect(card).toBeVisible();
  await expect(card.getByText("Meaning", { exact: true })).toBeVisible();
  // A pure meaning match has none of the keyword reasons.
  await expect(card.getByText("Body", { exact: true })).toHaveCount(0);
  await expect(
    card.getByRole("link", { name: "Saturday afternoon" }),
  ).toHaveAttribute("href", new RegExp(ids.get("Saturday afternoon")!));
  expect(await resultTitles(page)).toEqual(["Saturday afternoon"]);
  await expect(page.getByText("Still preparing")).toHaveCount(0);

  await page.screenshot({
    caret: "initial",
    path: test.info().outputPath("memotrail-semantic-search-desktop.png"),
  });

  // The same description in Chinese finds it too.
  await page.goto("/search?q=" + encodeURIComponent("修自行车的人"));
  await expect(resultCard(page, "Saturday afternoon")).toBeVisible();
});

test("A keyword query still ranks by words and adds meaning matches after them", async ({
  page,
  workspace,
}) => {
  await seed(workspace.client, workspace.owner, [
    friend,
    ...unrelated,
    {
      body: "Short list for the weekend.",
      title: "Bike notes",
    },
    {
      body: "I rode my bike to the river.",
      title: "River ride",
    },
  ]);
  await waitUntilIndexed(page, workspace.client);

  await page.goto("/search?q=bike");
  await expect(resultCard(page, "Bike notes")).toBeVisible();
  expect(await resultTitles(page)).toEqual([
    "Bike notes",
    "River ride",
    "Saturday afternoon",
  ]);
  await expect(
    resultCard(page, "Bike notes").getByText("Title", { exact: true }),
  ).toBeVisible();
  await expect(
    resultCard(page, "River ride").getByText("Body", { exact: true }),
  ).toBeVisible();
  const meaningOnly = resultCard(page, "Saturday afternoon");
  await expect(meaningOnly.getByText("Meaning", { exact: true })).toBeVisible();
  await expect(meaningOnly.getByText("Title", { exact: true })).toHaveCount(0);
  await expect(meaningOnly.getByText("Body", { exact: true })).toHaveCount(0);

  // A quoted phrase asks for exactly those words, so meaning stays out of it.
  await page.goto("/search?q=" + encodeURIComponent('"my bike"'));
  expect(await resultTitles(page)).toEqual(["River ride"]);
});

test("Filters constrain meaning matches too", async ({ page, workspace }) => {
  await seed(workspace.client, workspace.owner, [
    friend,
    {
      body: "The workshop man adjusted my bike frame and tuned the gears.",
      date: { precision: "month", start: "2019-03-02T12:00:00Z" },
      tag: "Shop",
      title: "Old wheels",
    },
    {
      body: "A year of riding a commuter everywhere.",
      subtype: "chapter",
      title: "Riding years",
    },
    ...unrelated,
  ]);
  await waitUntilIndexed(page, workspace.client);

  const description = encodeURIComponent("the mechanic who repairs bicycles");
  await page.goto("/search?q=" + description);
  expect((await resultTitles(page)).sort()).toEqual([
    "Old wheels",
    "Riding years",
    "Saturday afternoon",
  ]);

  await page.goto(`/search?q=${description}&tag=Neighbors`);
  expect(await resultTitles(page)).toEqual(["Saturday afternoon"]);

  await page.goto(`/search?q=${description}&type=chapter`);
  expect(await resultTitles(page)).toEqual(["Riding years"]);

  await page.goto(`/search?q=${description}&type=entry`);
  expect((await resultTitles(page)).sort()).toEqual([
    "Old wheels",
    "Saturday afternoon",
  ]);

  await page.goto(`/search?q=${description}&from=2026-01-01&to=2026-12-31`);
  expect(await resultTitles(page)).toEqual(["Saturday afternoon"]);

  await page.goto(`/search?q=${description}&tag=Nobody`);
  await expect(
    page.getByRole("heading", { name: "No Entries match", exact: true }),
  ).toBeVisible();
  expect(await resultTitles(page)).toEqual([]);
});

test("Search keeps working with words alone when the service is down", async ({
  page,
  workspace,
}) => {
  await seed(workspace.client, workspace.owner, [
    friend,
    ...unrelated,
    { body: "I rode my bike to the river.", title: "River ride" },
  ]);
  await waitUntilIndexed(page, workspace.client);

  // The fake answers 503 to any query containing the sentinel, like an outage.
  await page.goto(
    "/search?q=" + encodeURIComponent(`bike or ${OUTAGE_SENTINEL}`),
  );
  // While a streamed Suspense boundary swaps in, the page can briefly hold a hidden copy of the
  // notice, so a page-wide match is ambiguous. The search region only matches the shown one.
  await expect(
    page
      .getByRole("search", { name: "Library search" })
      .getByText("Search by meaning is unavailable right now"),
  ).toBeVisible();
  expect(await resultTitles(page)).toEqual(["River ride"]);
  await expect(resultCard(page, "River ride").getByText("Body")).toBeVisible();
  await expect(page.getByText("Meaning", { exact: true })).toHaveCount(0);
  await expect(page.getByText("Search unavailable")).toHaveCount(0);
});
