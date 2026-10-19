import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import type { Locator, Page } from "@playwright/test";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { expect, test } from "./helpers/workspace-test";
import { occurrenceStartField } from "./helpers/occurrence";

// The scripted provider the e2e server starts. It never reaches a real model.
test.skip(
  process.env.MEMOTRAIL_E2E_LIVE_AI === "1",
  "These scenarios read the scripted provider.",
);
// Dates are checked in one zone, so the day a review reads does not depend on the machine.
test.use({ timezoneId: "UTC" });

const firstCompile = { timeout: 90_000 };
const fakePort = Number(process.env.MEMOTRAIL_E2E_PORT || "3100") + 2000;

type SentRequest = {
  model: string;
  stage: string;
  input: string;
  hasImages: boolean;
  status: number;
};

/** What the scripted provider has been sent whose input holds `contains`. */
async function sent(contains: string, stage?: string) {
  const url = new URL(`http://127.0.0.1:${fakePort}/__requests`);
  url.searchParams.set("contains", contains);
  if (stage) url.searchParams.set("stage", stage);
  return (await (await fetch(url)).json()) as SentRequest[];
}

type SeedEntry = {
  title: string;
  body: string;
  day: string;
  tags?: string[];
  firstTime?: boolean;
};

const marker = () => `Z${randomUUID().slice(0, 7)}`;

/** The scheduling state of Chapter suggestions is never readable by the person, so tests use the admin key. */
function adminClient() {
  const env = JSON.parse(
    execFileSync("supabase", ["status", "-o", "json"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }),
  );
  return createClient(env.API_URL, env.SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
}

/** Makes the next visit to Timeline start a suggestion run, as if the month had passed. */
async function resetSuggestionSchedule(owner: string) {
  const { error } = await adminClient()
    .from("chapter_suggestion_state")
    .update({ last_run_at: null, last_entry_count: 0, leased_until: null })
    .eq("owner_id", owner);
  expect(error).toBeNull();
}

async function suggestionState(owner: string) {
  const { data, error } = await adminClient()
    .from("chapter_suggestion_state")
    .select("last_run_at")
    .eq("owner_id", owner)
    .maybeSingle();
  expect(error).toBeNull();
  return data;
}

/** Ids of the named tags, creating the ones this account does not have yet. */
async function seedTags(
  client: SupabaseClient,
  owner: string,
  names: string[],
) {
  const existing = await client.from("tags").select("id,name");
  expect(existing.error).toBeNull();
  const ids = new Map<string, string>(
    (existing.data ?? []).map((tag) => [tag.name as string, tag.id as string]),
  );
  const missing = [...new Set(names)].filter((name) => !ids.has(name));
  if (missing.length > 0) {
    const rows = missing.map((name) => ({
      id: randomUUID(),
      owner_id: owner,
      name,
    }));
    expect((await client.from("tags").insert(rows)).error).toBeNull();
    for (const row of rows) ids.set(row.name, row.id);
  }
  return ids;
}

/** Entries dated on one day each, with tags, in the order given. Returns their ids. */
async function seedEntries(
  client: SupabaseClient,
  owner: string,
  seeds: SeedEntry[],
) {
  const tags = await seedTags(
    client,
    owner,
    seeds.flatMap((seed) => seed.tags ?? []),
  );
  const ids = seeds.map(() => randomUUID());
  expect(
    (
      await client.from("entries").insert(
        seeds.map((seed, index) => ({
          id: ids[index],
          owner_id: owner,
          title: seed.title,
          body: seed.body,
          item_kind: "entry",
          item_subtype: "entry",
          is_first_time: seed.firstTime === true,
          occurred_start: `${seed.day}T12:00:00Z`,
          occurred_end: null,
          occurred_timezone: "UTC",
          date_precision: "day",
        })),
      )
    ).error,
  ).toBeNull();
  const links = seeds.flatMap((seed, index) =>
    (seed.tags ?? []).map((name) => ({
      entry_id: ids[index],
      owner_id: owner,
      tag_id: tags.get(name)!,
    })),
  );
  if (links.length > 0)
    expect((await client.from("entry_tags").insert(links)).error).toBeNull();
  return ids;
}

async function seedChapter(
  client: SupabaseClient,
  owner: string,
  chapter: { title: string; start: string; end: string | null; note?: string },
) {
  const id = randomUUID();
  expect(
    (
      await client.from("entries").insert({
        id,
        owner_id: owner,
        title: chapter.title,
        body: chapter.note ?? "",
        item_kind: "entry",
        item_subtype: "chapter",
        occurred_start: `${chapter.start}T12:00:00Z`,
        occurred_end: chapter.end ? `${chapter.end}T12:00:00Z` : null,
        occurred_timezone: "UTC",
        date_precision: "day",
      })
    ).error,
  ).toBeNull();
  return id;
}

const daysAgo = (count: number) =>
  new Date(Date.now() - count * 86_400_000).toISOString().slice(0, 10);

/** The six Entries of a job search, English and Chinese, the first one a First Time. */
const searchEntries = (extra: Partial<Record<number, string>> = {}) =>
  [
    {
      title: "First application sent",
      body: "I sent my first application today. It felt strange to press the button after so long.",
      day: "2026-03-05",
      tags: ["work", "hope"],
      firstTime: true,
    },
    {
      title: "Waiting for answers",
      body: "Nothing came back this week. Waiting is the hardest part of all of this.",
      day: "2026-03-24",
      tags: ["work"],
    },
    {
      title: "面试之后",
      body: "今天面试结束了。我觉得自己讲得还不错，但还是很紧张。",
      day: "2026-04-12",
      tags: ["work", "hope"],
    },
    {
      title: "A long walk",
      body: "I walked by the river for an hour. Everything felt a little lighter afterwards.",
      day: "2026-05-03",
      tags: ["walk"],
    },
    {
      title: "Second round",
      body: "The second round was tough, but I stayed calm. I want this job more now.",
      day: "2026-05-27",
      tags: ["work"],
    },
    {
      title: "收到了录用通知",
      body: "今天收到了录用通知。我把邮件读了三遍才相信。",
      day: "2026-06-14",
      tags: ["work", "hope"],
    },
  ].map((seed, index) =>
    extra[index] ? { ...seed, body: `${seed.body} ${extra[index]}` } : seed,
  ) satisfies SeedEntry[];

// While a refresh streams in, React can keep the previous panel in the page,
// hidden, for a moment. Only the one on screen is the panel.
const panelOf = (page: Page) => page.locator("[data-ui-review-panel]:visible");
const disclosureOf = (page: Page) =>
  page.getByRole("dialog", { name: "Before Claude reads your Entries" });

/**
 * Makes a review from a Chapter or year page that has not been turned on yet: the first press
 * opens the disclosure, and agreeing starts the review. A click made before hydration is retried.
 */
async function makeFirstReview(page: Page, panel: Locator) {
  const dialog = disclosureOf(page);
  await expect(async () => {
    if (!(await dialog.isVisible()))
      await panel.getByRole("button", { name: "Make a review" }).click();
    await expect(dialog).toBeVisible({ timeout: 2_000 });
  }).toPass(firstCompile);
  await dialog.getByRole("button", { name: "Turn on and make review" }).click();
}

/** Makes a review once reviews are on, retrying a click made before hydration. */
async function makeReview(page: Page, panel: Locator) {
  // The scripted provider can finish before the progress line is seen, so a
  // finished review also shows the click was taken.
  const started = panel
    .getByRole("status")
    .or(panel.getByText("Written by AI"))
    .first();
  await expect(async () => {
    if (!(await started.isVisible()))
      await panel.getByRole("button", { name: "Make a review" }).click();
    await expect(started).toBeVisible({ timeout: 2_000 });
  }).toPass(firstCompile);
}

const generated = { timeout: 60_000 };

async function reviewRows(client: SupabaseClient) {
  const { data, error } = await client
    .from("entry_reviews")
    .select("id,scope,chapter_id");
  expect(error).toBeNull();
  return data ?? [];
}

test("Asking for a Chapter review shows the disclosure, then a labeled review whose quotes are the person's own words", async ({
  page,
  workspace: { client, owner },
}) => {
  test.setTimeout(240_000);
  const uiErrors: string[] = [];
  page.on("pageerror", (error) => uiErrors.push(error.message));
  const name = `2026 job search ${marker()}`;
  const seeds = searchEntries();
  const ids = await seedEntries(client, owner, seeds);
  const chapterId = await seedChapter(client, owner, {
    title: name,
    start: "2026-03-01",
    end: "2026-06-30",
    note: "Looking for a role that fits me.",
  });
  const email = (await client.auth.getUser()).data.user!.email!;

  await page.goto(`/items/${chapterId}`);
  const panel = panelOf(page);
  await expect(
    panel.getByRole("heading", { name: "Looking back", exact: true }),
  ).toBeVisible(firstCompile);
  // Before anything is sent, the page says what would be.
  await expect(panel).toContainText(
    "MemoTrail sends the writing of this Chapter and its 6 Entries, text only, to Anthropic to write the review.",
  );
  await expect(panel).not.toContainText("Written by AI");

  const dialog = disclosureOf(page);
  await makeFirstReview(page, panel);
  await expect(dialog).toBeHidden();
  await expect(panel.getByRole("status")).toContainText("Reading 6 Entries");

  await expect(panel.getByText("Written by AI")).toBeVisible(generated);
  await expect(panel).toContainText("From 6 Entries");

  // The same disclosure can be read again from Settings; here, check what it promised.
  await page.goto("/settings");
  await page
    .getByRole("button", { name: "What is sent and to whom" })
    .click(firstCompile);
  const reread = disclosureOf(page);
  await expect(
    reread.getByRole("heading", { name: "What is sent" }),
  ).toBeVisible();
  await expect(reread).toContainText(
    "Anthropic deletes it automatically within 30 days.",
  );
  await expect(reread).toContainText(
    "Photos, Locations, your name, and your email address are never sent.",
  );
  const sources = reread.getByRole("link");
  await expect(sources).toHaveCount(3);
  for (const href of await sources.evaluateAll((links) =>
    links.map((link) => link.getAttribute("href")),
  ))
    expect(href).toMatch(
      /^https:\/\/(privacy\.claude\.com|www\.anthropic\.com)\//,
    );
  await reread.getByRole("button", { name: "Close" }).first().click();
  await page.goto(`/items/${chapterId}`);

  // From your Entries: facts counted from the person's own Entries, not written by Claude.
  const records = panel.getByRole("region", { name: "From your Entries" });
  await expect(records).toContainText("6 Entries");
  await expect(records).toContainText("1 First Time");
  await expect(
    records.getByRole("link", { name: /First application sent/ }),
  ).toHaveAttribute("href", `/items/${ids[0]}`);

  // Claude's reading is labeled once, beside "Looking back", and named again where it ends.
  for (const heading of ["How it felt", "What kept coming up"])
    await expect(panel.getByRole("region", { name: heading })).toBeVisible();
  await expect(panel.getByText("Written by AI")).toHaveCount(1);
  await expect(panel).toContainText(
    "Written by Claude, an AI model made by Anthropic",
  );
  const themes = panel.getByRole("region", { name: "What kept coming up" });
  await expect(themes).toContainText("Work");
  // Each theme opens the Entries it came from.
  const cited = themes.getByRole("button", { expanded: false }).first();
  await cited.click();
  await expect(
    themes.locator("[data-ui-entry-row]").first().getByRole("link"),
  ).toHaveAttribute("href", /^\/items\//);

  // In your words: four quotes, each copied exactly from a seeded Entry.
  const words = panel.getByRole("region", { name: "In your words" });
  const quotes = words.locator("blockquote");
  await expect(quotes).toHaveCount(4);
  for (const text of await quotes.allTextContents())
    expect(seeds.some((seed) => seed.body.includes(text))).toBe(true);
  await page.screenshot({
    animations: "disabled",
    caret: "initial",
    fullPage: true,
    path: test.info().outputPath("memotrail-chapter-review-desktop.png"),
  });
  await words.locator("figure").first().getByRole("link").click();
  await expect(page).toHaveURL(`/items/${ids[0]}`);

  // The made review is listed under Reviews and opens its Chapter.
  await page.goto("/reviews");
  const chapters = page.getByRole("list", { name: "Chapters" });
  await expect(chapters).toContainText(name, firstCompile);
  await expect(chapters).toContainText("Review made");
  await expect(
    chapters.getByRole("link", { name: new RegExp(name) }),
  ).toHaveAttribute("href", `/items/${chapterId}`);

  // What left the app: one request, text only, and nothing but the seeded Entries.
  const requests = await sent(name);
  expect(requests).toHaveLength(1);
  const [request] = requests;
  expect(request).toMatchObject({
    model: "claude-sonnet-5-5",
    stage: "review",
    hasImages: false,
    status: 200,
  });
  const body = JSON.parse(request.input);
  expect(body.subject).toMatchObject({ kind: "chapter", name });
  // The Chapter's own writing is sent as E0, and the Entries inside it follow in time order.
  expect(body.subject.note).toBe("E0");
  const note = body.entries.find(
    (entry: { role: string }) => entry.role === "chapter_note",
  );
  expect(
    note.passages.map((passage: { text: string }) => passage.text).join(" "),
  ).toBe("Looking for a role that fits me.");
  expect(
    body.entries
      .filter((entry: { role: string }) => entry.role === "entry")
      .map((entry: { title: string }) => entry.title),
  ).toEqual(seeds.map((seed) => seed.title));
  for (const entry of body.entries)
    expect(Object.keys(entry).sort()).toEqual([
      "date",
      "firstTime",
      "id",
      "passages",
      "role",
      "tags",
      "title",
      "trimmed",
    ]);
  expect(request.input).not.toContain(email);
  expect(request.input).not.toContain(owner);
  for (const id of [chapterId, ...ids]) expect(request.input).not.toContain(id);
  expect(uiErrors).toEqual([]);
});

test("A quote that no longer matches its Entry is hidden and counted, and an unknown passage is never shown", async ({
  page,
  workspace: { client, owner },
}) => {
  test.setTimeout(240_000);
  const name = `Quote check ${marker()}`;
  const seeds = searchEntries();
  const ids = await seedEntries(client, owner, seeds);
  const chapterId = await seedChapter(client, owner, {
    title: name,
    start: "2026-03-01",
    end: "2026-06-30",
  });

  await page.goto(`/items/${chapterId}`);
  const panel = panelOf(page);
  await makeFirstReview(page, panel);
  await expect(panel.getByText("Written by AI")).toBeVisible(generated);
  const quotes = panel
    .getByRole("region", { name: "In your words" })
    .locator("blockquote");
  await expect(quotes).toHaveCount(4);

  // The person edits the first quoted Entry so the quoted words are gone.
  const first = await quotes.first().textContent();
  expect(
    (
      await client
        .from("entries")
        .update({ body: seeds[0].body.replace(first!, "").trim() })
        .eq("id", ids[0])
    ).error,
  ).toBeNull();
  await page.reload();
  await expect(quotes).toHaveCount(3);
  await expect(panel).toContainText(
    "1 quote is hidden because its Entry was edited or moved to Trash.",
  );
  await expect(panel).toContainText(
    "1 Entry in this Chapter is new or changed since this review.",
  );
  await expect(
    panel.getByRole("button", { name: "Write again" }).first(),
  ).toBeVisible();

  // A second edit makes the wording plural.
  const second = await quotes.first().textContent();
  expect(
    (
      await client
        .from("entries")
        .update({ body: seeds[1].body.replace(second!, "").trim() || "Gone." })
        .eq("id", ids[1])
    ).error,
  ).toBeNull();
  await page.reload();
  await expect(quotes).toHaveCount(2);
  await expect(panel).toContainText(
    "2 quotes are hidden because their Entries were edited or moved to Trash.",
  );

  // The provider points at a passage that does not exist: only real quotes are kept.
  const badName = `Unknown passage ${marker()}`;
  const badSeeds = searchEntries({ 4: "FAKE_AI_BAD_QUOTE" });
  await seedEntries(
    client,
    owner,
    badSeeds.map((seed) => ({
      ...seed,
      day: seed.day.replace("2026-", "2025-"),
    })),
  );
  const badChapter = await seedChapter(client, owner, {
    title: badName,
    start: "2025-03-01",
    end: "2025-06-30",
  });
  await page.goto(`/items/${badChapter}`);
  await makeReview(page, panel);
  await expect(panel.getByText("Written by AI")).toBeVisible(generated);
  const kept = await panel
    .getByRole("region", { name: "In your words" })
    .locator("blockquote")
    .allTextContents();
  expect(kept).toHaveLength(4);
  for (const text of kept)
    expect(badSeeds.some((seed) => seed.body.includes(text))).toBe(true);
  await expect(panel).not.toContainText("hidden because");
  const requests = await sent(badName);
  expect(requests).toHaveLength(1);
  expect(requests[0].input).toContain("FAKE_AI_BAD_QUOTE");
});

test("Trash hides what came from an Entry, Restore brings it back, and Delete forever deletes the review", async ({
  page,
  workspace: { client, owner },
}) => {
  test.setTimeout(300_000);
  const name = `Trash check ${marker()}`;
  const seeds = searchEntries();
  const ids = await seedEntries(client, owner, seeds);
  const chapterId = await seedChapter(client, owner, {
    title: name,
    start: "2026-03-01",
    end: "2026-06-30",
  });
  await page.goto(`/items/${chapterId}`);
  const panel = panelOf(page);
  await makeFirstReview(page, panel);
  await expect(panel.getByText("Written by AI")).toBeVisible(generated);
  const quotes = panel
    .getByRole("region", { name: "In your words" })
    .locator("blockquote");
  await expect(quotes).toHaveCount(4);
  const title = seeds[0].title;
  await expect(
    panel.getByRole("link", { name: new RegExp(title) }).first(),
  ).toBeVisible();

  // Move the first cited Entry to Trash.
  await page.goto(`/items/${ids[0]}`);
  await page.getByRole("button", { name: "Move to Trash" }).click(firstCompile);
  await page
    .getByRole("dialog", { name: `Move “${title}” to Trash?` })
    .getByRole("button", { name: "Move to Trash", exact: true })
    .click();
  await expect(page).toHaveURL(/\/library$/, firstCompile);

  await page.goto(`/items/${chapterId}`);
  await expect(quotes).toHaveCount(3);
  await expect(panel).toContainText(
    "1 Entry this review read is in Trash, so what came from it is hidden.",
  );
  await expect(
    panel.getByRole("link", { name: new RegExp(title) }),
  ).toHaveCount(0);

  // Restore it from Trash: the quote and the citations return.
  await page.goto("/trash");
  const card = page.getByRole("article").filter({ hasText: title });
  await expect(card).toBeVisible(firstCompile);
  await card.getByRole("button", { name: "Restore", exact: true }).click();
  await expect(card).toHaveCount(0, firstCompile);
  await page.goto(`/items/${chapterId}`);
  await expect(quotes).toHaveCount(4);
  await expect(panel).not.toContainText("is in Trash");

  // Trash it again and delete it forever: the confirmation says reviews go too.
  await page.goto(`/items/${ids[0]}`);
  await page.getByRole("button", { name: "Move to Trash" }).click(firstCompile);
  await page
    .getByRole("dialog", { name: `Move “${title}” to Trash?` })
    .getByRole("button", { name: "Move to Trash", exact: true })
    .click();
  await expect(page).toHaveURL(/\/library$/, firstCompile);
  await page.goto("/trash");
  await expect(card).toBeVisible(firstCompile);
  const confirm = page.getByRole("dialog");
  await expect(async () => {
    if (!(await confirm.isVisible()))
      await card
        .getByRole("button", { name: "Delete forever", exact: true })
        .click();
    await expect(confirm).toBeVisible({ timeout: 2_000 });
  }).toPass(firstCompile);
  await expect(confirm).toContainText(
    "Reviews that read these Entries are deleted too.",
  );
  await confirm
    .getByRole("button", { name: "Delete forever", exact: true })
    .click();
  await expect(card).toHaveCount(0, firstCompile);

  await expect.poll(() => reviewRows(client), firstCompile).toEqual([]);
  await page.goto(`/items/${chapterId}`);
  await expect(
    panel.getByRole("button", { name: "Make a review" }),
  ).toBeVisible();
  await expect(panel).not.toContainText("Written by AI");
});

test("Turning reviews off in Settings deletes the saved reviews", async ({
  page,
  workspace: { client, owner },
}) => {
  test.setTimeout(240_000);
  const name = `Turn off check ${marker()}`;
  await seedEntries(client, owner, searchEntries());
  const chapterId = await seedChapter(client, owner, {
    title: name,
    start: "2026-03-01",
    end: "2026-06-30",
  });
  await page.goto(`/items/${chapterId}`);
  const panel = panelOf(page);
  await makeFirstReview(page, panel);
  await expect(panel.getByText("Written by AI")).toBeVisible(generated);
  expect(await reviewRows(client)).toHaveLength(1);

  await page.goto("/settings");
  const reviews = page.getByRole("checkbox", {
    name: "Chapter and year reviews",
  });
  await expect(reviews).toBeChecked(firstCompile);
  const confirm = page.getByRole("dialog", { name: "Turn off reviews?" });
  await expect(async () => {
    if (!(await confirm.isVisible())) await reviews.click();
    await expect(confirm).toBeVisible({ timeout: 2_000 });
  }).toPass(firstCompile);
  await expect(confirm).toContainText("Your 1 saved review will be deleted.");
  await confirm.getByRole("button", { name: "Turn off and delete" }).click();
  await expect(reviews).not.toBeChecked();
  await expect(page.getByText("Reviews are off.")).toBeVisible();

  expect(await reviewRows(client)).toEqual([]);
  await page.goto(`/items/${chapterId}`);
  await expect(panel).not.toContainText("Written by AI");
  await expect(
    panel.getByRole("button", { name: "Make a review" }),
  ).toBeVisible();
  // Turning it off sent nothing.
  expect(await sent(name)).toHaveLength(1);
});

test("A year review is made from Reviews, and a quiet notice offers a Chapter that just ended", async ({
  page,
  workspace: { client, owner },
}) => {
  test.setTimeout(300_000);
  const uiErrors: string[] = [];
  page.on("pageerror", (error) => uiErrors.push(error.message));
  // The scripted provider keeps every request for the server's life, so the one this test
  // looks up carries its own marker.
  const spring = `Spring cleaning ${marker()}`;
  const seeds: SeedEntry[] = [
    ["2025-01-12", "A cold January start", ["winter"]],
    ["2025-03-03", spring, ["home"]],
    ["2025-05-20", "Dinner with the whole family", ["family", "home"]],
    ["2025-07-08", "A week by the lake", ["family"]],
    ["2025-09-14", "Back to a routine", ["home"]],
    ["2025-11-30", "Looking back on the year", ["winter", "family"]],
  ].map(([day, title, tags]) => ({
    day: day as string,
    title: title as string,
    body: `${title}. It was a quiet day, and I wrote it down so I would remember it later.`,
    tags: tags as string[],
  }));
  await seedEntries(client, owner, seeds);

  // Reviews is a destination of its own in the sidebar.
  await page.goto("/timeline");
  await page
    .getByRole("navigation", { name: "Primary navigation" })
    .getByRole("link", { name: "Reviews" })
    .click(firstCompile);
  await expect(page).toHaveURL(/\/reviews$/);
  await expect(
    page.getByRole("heading", { level: 1, name: "Reviews" }),
  ).toBeVisible();
  const years = page.getByRole("list", { name: "Years" });
  await expect(years.getByRole("listitem")).toHaveCount(1);
  await expect(years).toContainText("2025");
  await expect(years).toContainText("6 Entries");
  await expect(page.getByRole("list", { name: "Chapters" })).toHaveCount(0);
  await years.getByRole("link", { name: /2025/ }).click();
  await expect(page).toHaveURL(/\/reviews\/2025$/);
  await expect(
    page.getByRole("heading", { level: 1, name: "2025 in review" }),
  ).toBeVisible();

  const panel = panelOf(page);
  await expect(panel).toContainText(
    "MemoTrail sends the writing of your 6 Entries from 2025, text only, to Anthropic to write the review.",
  );
  await makeFirstReview(page, panel);
  // A year's review is labeled in the page's own meta line, under its title.
  const header = page.locator("[data-ui-page-header]");
  await expect(header.getByText("Written by AI")).toBeVisible(generated);
  await expect(header).toContainText("From 6 Entries");
  await expect(
    panel.getByRole("region", { name: "From your Entries" }),
  ).toContainText("6 Entries");
  await expect(
    panel.getByRole("button", { name: "Write again" }),
  ).toBeVisible();
  await expect(
    panel.getByRole("button", { name: "Delete review" }),
  ).toBeVisible();
  await expect(
    panel.getByRole("region", { name: "In your words" }).locator("blockquote"),
  ).toHaveCount(4);
  const requests = await sent(spring, "review");
  expect(requests).toHaveLength(1);
  expect(JSON.parse(requests[0].input).subject).toEqual({
    kind: "year",
    year: 2025,
  });
  await page.goto("/reviews");
  await expect(years).toContainText("Review made");

  // Two Chapters ended within the last sixty days, each with five Entries.
  await seedEntries(
    client,
    owner,
    [55, 50, 45, 40, 36, 30].map((age, index) => ({
      day: daysAgo(age),
      title: `Packing day ${index + 1}`,
      body: `Packing day ${index + 1}. Another box went into the car and it felt like progress.`,
      tags: ["moving"],
    })),
  );
  const recent = `Moving out ${marker()}`;
  const earlier = `Last term ${marker()}`;
  const recentId = await seedChapter(client, owner, {
    title: recent,
    start: daysAgo(60),
    end: daysAgo(20),
  });
  await seedChapter(client, owner, {
    title: earlier,
    start: daysAgo(59),
    end: daysAgo(35),
  });
  // In January through March the year just ended comes first; retire it so the Chapters show.
  const today = daysAgo(0);
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const { data } = await client.rpc("review_notice", { p_local_date: today });
    if (!data || data.kind !== "year") break;
    await client.rpc("resolve_review_notice", { p_subject: data.subject });
  }

  await page.goto("/");
  const notice = page.getByRole("region", { name: "Review notice" });
  await expect(notice).toBeVisible(firstCompile);
  await expect(notice).toContainText(
    `${recent} has ended. See what this Chapter held.`,
  );
  await notice.scrollIntoViewIfNeeded();
  await page.screenshot({
    animations: "disabled",
    caret: "initial",
    path: test.info().outputPath("memotrail-review-notice-desktop.png"),
  });
  // Following the notice opens the Chapter and retires the notice for good.
  await notice.getByRole("link", { name: "Open Chapter" }).click();
  await expect(page).toHaveURL(`/items/${recentId}`);
  await page.goto("/");
  await expect(notice).toContainText(`${earlier} has ended.`, firstCompile);
  // Not now removes the second one, and it stays gone across reloads.
  await notice.getByRole("button", { name: "Not now" }).click();
  await expect(notice).toHaveCount(0);
  await page.reload();
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  await expect(notice).toHaveCount(0);
  expect(uiErrors).toEqual([]);
});

test("Chapter suggestions are opt in, appear on Timeline, become a Chapter only when added, and a dismissed stretch does not return", async ({
  page,
  workspace: { client, owner },
}) => {
  test.setTimeout(360_000);
  const uiErrors: string[] = [];
  page.on("pageerror", (error) => uiErrors.push(error.message));
  const label = marker();
  const climbing = Array.from({ length: 14 }, (_, index) => ({
    day: daysAgo(100 - Math.round((index * 88) / 13)),
    title: `Climbing session ${index + 1} ${label}`,
    body: `Went to the climbing gym again. Session ${index + 1} felt stronger than the last one.`,
    tags: ["climbing"],
  }));
  await seedEntries(client, owner, climbing);
  const first = climbing[0].day;

  // Nothing is run, and nothing is sent, until the person turns it on.
  await page.goto("/timeline");
  await expect(page.getByText("Suggested Chapter")).toHaveCount(
    0,
    firstCompile,
  );
  expect(await sent(label)).toHaveLength(0);

  await page.goto("/settings");
  const suggest = page.getByRole("checkbox", { name: "Suggest Chapters" });
  await expect(suggest).not.toBeChecked(firstCompile);
  const disclosure = disclosureOf(page);
  await expect(async () => {
    if (!(await disclosure.isVisible())) await suggest.click();
    await expect(disclosure).toBeVisible({ timeout: 2_000 });
  }).toPass(firstCompile);
  await disclosure
    .getByRole("button", { name: "Turn on", exact: true })
    .click();
  await expect(suggest).toBeChecked();

  // The run happens after the setting is saved; a visit to Timeline asks again if it is due.
  await expect
    .poll(
      async () =>
        (
          await client
            .from("chapter_suggestions")
            .select("id")
            .eq("status", "pending")
        ).data?.length,
      { timeout: 45_000 },
    )
    .toBe(1);
  const requests = await sent(label, "suggestions");
  expect(requests).toHaveLength(1);
  expect(requests[0]).toMatchObject({
    model: "claude-sonnet-5-5",
    hasImages: false,
  });
  expect(JSON.parse(requests[0].input).entries).toHaveLength(14);

  await page.goto("/timeline");
  const card = page.getByRole("region", { name: "Climbing" });
  await expect(card).toBeVisible(firstCompile);
  await expect(card).toContainText("Suggested Chapter");
  await expect(card.getByText("Suggested by AI")).toBeVisible();
  await expect(card).toContainText("Based on 14 Entries");
  await page.screenshot({
    animations: "disabled",
    caret: "initial",
    path: test.info().outputPath("memotrail-chapter-suggestion-desktop.png"),
  });
  await card.getByRole("button", { name: "Review and add" }).click();

  // Nothing is a Chapter yet: the editor opens in Chapter mode with the name and dates filled.
  const editor = page.getByRole("dialog", { name: "Add a Chapter" });
  await expect(editor).toBeVisible();
  await expect(
    editor.getByRole("checkbox", { name: /^Chapter/ }),
  ).toBeChecked();
  await expect(editor.getByLabel("Title", { exact: true })).toHaveValue(
    "Climbing",
  );
  await expect(occurrenceStartField(editor)).toHaveValue(first.slice(0, 7));
  await expect(
    editor.getByRole("checkbox", { name: "Present", exact: true }),
  ).toBeChecked();
  expect(
    (await client.from("entries").select("id").eq("item_subtype", "chapter"))
      .data,
  ).toEqual([]);
  await editor.getByRole("button", { name: "Add", exact: true }).click();
  await expect(page.getByText("Chapter added.")).toBeVisible();
  await expect(editor).not.toBeVisible();
  await expect(
    page
      .getByRole("region", { name: "Timeline by year" })
      .getByRole("link", { name: /Climbing/ }),
  ).toBeVisible();
  await expect(card).toHaveCount(0);
  await expect
    .poll(async () =>
      (await client.from("chapter_suggestions").select("status")).data?.map(
        (row) => row.status,
      ),
    )
    .toEqual(["confirmed"]);

  // A second stretch: run again, then dismiss it.
  const baking = Array.from({ length: 14 }, (_, index) => ({
    day: daysAgo(400 - Math.round((index * 80) / 13)),
    title: `Baking day ${index + 1} ${label}`,
    body: `Baked a new loaf today. Loaf ${index + 1} rose higher than the one before.`,
    tags: ["baking"],
  }));
  await seedEntries(client, owner, baking);
  await resetSuggestionSchedule(owner);
  await page.goto("/timeline");
  const second = page.getByRole("region", { name: "Baking" });
  await expect(async () => {
    await page.reload();
    await expect(second).toBeVisible({ timeout: 3_000 });
  }).toPass({ timeout: 60_000, intervals: [2_000] });
  await second.getByRole("button", { name: "Dismiss" }).click();
  await expect(second).toHaveCount(0);
  await expect(
    page.getByText("This suggestion won't come back."),
  ).toBeVisible();

  // Run once more: the dismissed stretch is not proposed again.
  const before = (await sent(label, "suggestions")).length;
  await resetSuggestionSchedule(owner);
  await page.goto("/timeline");
  await expect
    .poll(async () => (await sent(label, "suggestions")).length, {
      timeout: 45_000,
    })
    .toBe(before + 1);
  await expect
    .poll(async () => (await suggestionState(owner))?.last_run_at, {
      timeout: 30_000,
    })
    .not.toBeNull();
  await page.reload();
  await expect(second).toHaveCount(0);
  await expect(page.getByText("Suggested Chapter")).toHaveCount(0);
  expect(
    (
      await client
        .from("chapter_suggestions")
        .select("status")
        .eq("status", "pending")
    ).data,
  ).toEqual([]);
  expect(uiErrors).toEqual([]);
});

test("A provider outage shows a plain message and Try again, and nothing is sent again until it is pressed", async ({
  page,
  workspace: { client, owner },
}) => {
  test.setTimeout(240_000);
  const name = `Outage check ${marker()}`;
  await seedEntries(client, owner, searchEntries({ 2: "FAKE_AI_OUTAGE" }));
  const chapterId = await seedChapter(client, owner, {
    title: name,
    start: "2026-03-01",
    end: "2026-06-30",
  });
  await page.goto(`/items/${chapterId}`);
  const panel = panelOf(page);
  await makeFirstReview(page, panel);

  const failure = panel.getByRole("alert");
  await expect(failure).toBeVisible(generated);
  await expect(failure).toContainText(
    /Claude couldn't write this review|The review stopped before it finished/,
  );
  const retry = failure.getByRole("button", { name: "Try again" });
  await expect(retry).toBeVisible();
  await expect(panel).not.toContainText("Written by AI");
  await page.screenshot({
    animations: "disabled",
    caret: "initial",
    path: test.info().outputPath("memotrail-review-failure-desktop.png"),
  });

  // Leave it alone for a while: no second request is made on its own.
  expect(await sent(name)).toHaveLength(1);
  await page.waitForTimeout(6_000);
  await page.reload();
  await expect(failure).toBeVisible();
  expect(await sent(name)).toHaveLength(1);
  expect(await reviewRows(client)).toHaveLength(1);

  await retry.click();
  await expect
    .poll(async () => (await sent(name)).length, { timeout: 30_000 })
    .toBe(2);
});
