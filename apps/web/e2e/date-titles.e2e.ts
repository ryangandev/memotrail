import { expect, test } from "./helpers/workspace-test";

test("untitled Entries are named by their date and never wait to be organized", async ({
  page,
  workspace: { client, owner },
}) => {
  test.setTimeout(90_000);
  const profile = await client
    .from("profiles")
    .update({ display_name: "Test User" })
    .eq("user_id", owner);
  expect(profile.error).toBeNull();

  const untitled = {
    item_kind: "entry",
    item_subtype: "entry",
    owner_id: owner,
    title: null,
  };
  const inserted = await client
    .from("entries")
    .insert([
      {
        ...untitled,
        body: "Rain all morning, walked anyway.",
        created_at: "2026-10-18T08:00:00Z",
        // Already Monday in UTC, still Sunday where it was written.
        date_precision: "day",
        occurred_start: "2026-10-19T02:00:00Z",
        occurred_timezone: "America/Los_Angeles",
      },
      {
        ...untitled,
        body: "Started at the bakery.",
        created_at: "2026-10-17T08:00:00Z",
        date_precision: "month",
        occurred_start: "2026-09-01T12:00:00Z",
        occurred_timezone: "UTC",
      },
      {
        ...untitled,
        body: "Learned to swim.",
        created_at: "2026-10-16T08:00:00Z",
        date_precision: "year",
        occurred_start: "2024-01-01T12:00:00Z",
        occurred_timezone: "UTC",
      },
      {
        ...untitled,
        body: "A long weekend by the lake.",
        created_at: "2026-10-15T08:00:00Z",
        date_precision: "range",
        occurred_start: "2026-10-10T12:00:00Z",
        occurred_end: "2026-10-12T12:00:00Z",
        occurred_timezone: "UTC",
      },
      {
        ...untitled,
        body: "Painted the fence.",
        created_at: "2026-10-14T08:00:00Z",
        date_precision: "approximate",
        occurred_label: "Summer after college",
        occurred_start: "2022-07-01T12:00:00Z",
        occurred_timezone: "UTC",
      },
      {
        ...untitled,
        body: "Something worth keeping.",
        created_at: "2026-10-13T08:00:00Z",
        date_precision: "unknown",
      },
      {
        ...untitled,
        body: "Caught the early ferry.",
        created_at: "2026-10-11T08:00:00Z",
        date_precision: "exact",
        occurred_start: "2026-10-03T14:30:00Z",
        occurred_timezone: "America/Los_Angeles",
      },
      {
        ...untitled,
        body: "Already named.",
        created_at: "2026-10-12T08:00:00Z",
        date_precision: "day",
        occurred_start: "2026-10-01T12:00:00Z",
        occurred_timezone: "UTC",
        title: "A titled memory",
      },
    ])
    .select("id,body");
  expect(inserted.error).toBeNull();
  const rainID = inserted.data!.find((entry) =>
    entry.body.startsWith("Rain"),
  )!.id;
  const exactID = inserted.data!.find((entry) =>
    entry.body.startsWith("Caught"),
  )!.id;
  const named = [
    ["Sunday, October 18, 2026", "Rain all morning, walked anyway."],
    ["September 2026", "Started at the bakery."],
    ["2024", "Learned to swim."],
    ["October 10 - October 12, 2026", "A long weekend by the lake."],
    ["Summer after college", "Painted the fence."],
    ["Undated entry", "Something worth keeping."],
  ] as const;

  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto("/");
  await expect(
    page.getByRole("form", { name: "Quick capture", exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole("region", { name: "Needs organizing" }),
  ).toHaveCount(0);
  await expect(page.getByRole("link", { name: /To organize/ })).toHaveCount(0);
  const recent = page.getByRole("region", {
    name: "Recent Entries",
    exact: true,
  });
  for (const [title, note] of named.slice(0, 5)) {
    const row = recent.getByRole("link").filter({ hasText: note });
    await expect(row.getByRole("heading")).toHaveText(title);
    // The date already names it, so it is not repeated beside the title.
    await expect(row.getByText(title)).toHaveCount(1);
  }

  await page.goto("/library");
  const items = page.getByRole("region", { name: "Entries", exact: true });
  await expect(items.getByRole("listitem")).toHaveCount(8);
  for (const [title, note] of named) {
    const row = items.getByRole("listitem").filter({ hasText: note });
    await expect(row.getByRole("link")).toHaveAccessibleName(title);
    await expect(row.getByText(title)).toHaveCount(1);
    // The title already is the date, so the date column stays empty.
    await expect(row.locator("time")).toHaveCount(0);
  }
  // Under the October 2026 heading a date leaves out the year.
  await expect(
    items
      .getByRole("listitem")
      .filter({ hasText: "A titled memory" })
      .locator("time"),
  ).toHaveText("Oct 1");

  await page.keyboard.press("ControlOrMeta+k");
  const palette = page.getByRole("dialog", { name: "Search MemoTrail" });
  await palette.getByRole("searchbox").fill("rain all morning");
  await expect(
    palette.getByRole("button", { name: /Sunday, October 18, 2026/ }),
  ).toBeVisible();
  await page.keyboard.press("Escape");

  await items
    .getByRole("listitem")
    .filter({ hasText: "Rain all morning" })
    .getByRole("link")
    .click();
  await expect(page).toHaveURL(`/items/${rainID}`);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText(
    "Sunday, October 18, 2026",
  );
  await expect(page).toHaveTitle("Sunday, October 18, 2026 | MemoTrail");
  await expect(
    page
      .getByRole("main")
      .getByText("Rain all morning, walked anyway.", { exact: true }),
  ).toHaveCount(1);
  // The heading already is the date, so the Date fact would only repeat it.
  const facts = page.getByRole("article", { name: "Current item" });
  await expect(facts.getByText("Date", { exact: true })).toHaveCount(0);
  await page.goto(`/items/${exactID}`);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText(
    "Saturday, October 3, 2026",
  );
  // An exact moment keeps its Date fact, which adds the time.
  await expect(facts.getByText("Date", { exact: true })).toBeVisible();
  await expect(facts).toContainText("Oct 3, 2026, 7:30 AM");

  // Links saved before Needs organizing was retired still open Library.
  for (const retired of ["/inbox", "/library?show=needs-organizing"]) {
    await page.goto(retired);
    await expect(page).toHaveURL(/\/library(\?show=needs-organizing)?$/);
    await expect(
      page
        .getByRole("region", { name: "Entries", exact: true })
        .getByRole("listitem"),
    ).toHaveCount(8);
    await expect(
      page.getByRole("heading", { name: "Needs organizing" }),
    ).toHaveCount(0);
  }
  await page.goto(`/inbox?entry=${rainID}`);
  await expect(page).toHaveURL(new RegExp(`/items/${rainID}`));

  await page.goto("/library");
  await page.setViewportSize({ width: 390, height: 844 });
  await expect
    .poll(() =>
      page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
    )
    .toBe(true);
});
