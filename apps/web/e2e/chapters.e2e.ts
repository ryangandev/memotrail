import { randomUUID } from "node:crypto";
import { expect, test } from "./helpers/workspace-test";
import {
  fillOccurrenceEnd,
  fillOccurrenceStart,
  setOccurrencePrecision,
} from "./helpers/occurrence";

type Seed = {
  id: string;
  precision: "day" | "month" | "year" | "unknown";
  start: string | null;
  title: string;
};

const entry = (
  title: string,
  precision: Seed["precision"],
  start: string | null,
): Seed => ({ id: randomUUID(), precision, start, title });

test("Chapters and First Times are marks on Entries that appear on Timeline, Dashboard and Item pages", async ({
  page,
  workspace: { client, owner },
}) => {
  test.setTimeout(180_000);
  const uiErrors: string[] = [];
  page.on("pageerror", (error) => uiErrors.push(error.message));
  expect(
    (
      await client
        .from("profiles")
        .update({ birth_date: "1990-01-01", timezone: "America/New_York" })
        .eq("user_id", owner)
    ).error,
  ).toBeNull();

  const day = entry("Farmers market with Sam", "day", "2021-06-15T12:00:00Z");
  const month = entry("June notes", "month", "2021-06-01T12:00:00Z");
  const year = entry("A year of change", "year", "2021-01-01T12:00:00Z");
  const february = entry("Winter walk", "day", "2021-02-28T12:00:00Z");
  const unknown = entry("Undated recipe", "unknown", null);
  const hike = entry("Hiking alone", "day", "2020-05-04T12:00:00Z");
  const abroad = entry("Study abroad", "day", "2018-09-01T12:00:00Z");
  const exams = entry("Exam week", "day", "2019-01-15T12:00:00Z");
  const seeds = [day, month, year, february, unknown, hike, abroad, exams];
  expect(
    (
      await client.from("entries").insert(
        seeds.map((seed) => ({
          id: seed.id,
          owner_id: owner,
          title: seed.title,
          body: "",
          item_kind: "entry",
          item_subtype: "entry",
          occurred_start: seed.start,
          occurred_end: null,
          occurred_timezone: "UTC",
          date_precision: seed.precision,
        })),
      )
    ).error,
  ).toBeNull();

  // The chooser offers exactly the two marks.
  await page.goto("/timeline");
  await page.getByRole("button", { name: "Add to Timeline" }).first().click();
  const chooser = page.getByRole("dialog", { name: "What are you adding?" });
  await expect(chooser.getByRole("button", { name: /^Add / })).toHaveText([
    /Chapter/,
    /First Time/,
  ]);
  await chooser.getByRole("button", { name: "Add Chapter" }).click();

  // A Chapter needs a title before it can be saved.
  const editor = page.getByRole("dialog", { name: "Add a Chapter" });
  await expect(editor).toBeVisible();
  await expect(
    editor.getByRole("checkbox", { name: /^Chapter/ }),
  ).toBeChecked();
  await expect(
    editor.getByRole("checkbox", { name: /^First Time/ }),
  ).not.toBeChecked();
  await editor.getByRole("button", { name: "Add", exact: true }).click();
  await expect(editor.getByRole("alert")).toHaveText(
    "Give this Chapter a title.",
  );
  await editor.getByLabel("Title", { exact: true }).fill("Living in Portland");
  await setOccurrencePrecision(editor, "month");
  await fillOccurrenceStart(editor, "2021-03");
  await editor.getByRole("checkbox", { name: "Present", exact: true }).check();
  await editor.getByRole("button", { name: "Add", exact: true }).click();
  await expect(page.getByText("Chapter added.")).toBeVisible();
  await expect(editor).not.toBeVisible();

  const saved = await client
    .from("entries")
    .select("id,item_subtype,is_first_time,date_precision,occurred_end")
    .eq("owner_id", owner)
    .eq("title", "Living in Portland")
    .single();
  expect(saved.error).toBeNull();
  expect(saved.data).toMatchObject({
    item_subtype: "chapter",
    is_first_time: false,
    date_precision: "month",
    occurred_end: null,
  });
  const chapterId = saved.data!.id as string;

  // The Chapter is a bar on Timeline, named for its title and span.
  const timeline = page.getByRole("region", { name: "Timeline by year" });
  const bar = timeline.getByRole("link", { name: /Living in Portland/ });
  await expect(bar).toBeVisible();
  await expect(bar).toHaveAttribute("aria-label", /Since Mar 2021/);
  await expect(
    timeline.getByRole("link", { name: /Study abroad/ }),
  ).toHaveCount(0);

  await page.screenshot({
    animations: "disabled",
    caret: "initial",
    path: test.info().outputPath("memotrail-chapters-timeline.png"),
  });

  // Its page lists the Entries dated inside it, oldest first, and only those.
  await bar.click();
  await expect(page).toHaveURL(`/items/${chapterId}`);
  await expect(
    page.getByRole("heading", { name: "In this Chapter" }),
  ).toBeVisible();
  const inside = page.getByRole("list", { name: "Entries in this Chapter" });
  await expect(inside.getByRole("listitem")).toHaveCount(2);
  await expect(inside.getByRole("listitem").locator("strong")).toHaveText([
    "June notes",
    "Farmers market with Sam",
  ]);
  for (const title of ["A year of change", "Winter walk", "Undated recipe"])
    await expect(inside.getByText(title)).toHaveCount(0);

  await page.screenshot({
    animations: "disabled",
    caret: "initial",
    fullPage: true,
    path: test.info().outputPath("memotrail-chapters-item.png"),
  });

  // Dashboard Now shows the Chapter with its span and how long it has lasted.
  await page.goto("/");
  const now = page.getByRole("region", { name: "Now", exact: true });
  const nowItem = now.getByRole("link", { name: /Living in Portland/ });
  await expect(nowItem).toBeVisible();
  await expect(nowItem).toContainText("Since Mar 2021");
  await expect(nowItem).toContainText(/About \d+ years?/);

  // Checking First Time on an ordinary Entry puts it in First Times and on Timeline.
  await page.goto(`/items/${hike.id}`);
  await page.getByRole("button", { name: "Edit Entry" }).click();
  const hikeEditor = page.getByRole("dialog", { name: "Edit Entry" });
  await hikeEditor.getByRole("checkbox", { name: /^First Time/ }).check();
  await hikeEditor.getByRole("button", { name: "Save changes" }).click();
  await expect(hikeEditor).not.toBeVisible();
  await expect
    .poll(async () => {
      const { data } = await client
        .from("entries")
        .select("is_first_time,item_subtype")
        .eq("id", hike.id)
        .single();
      return data;
    })
    .toEqual({ is_first_time: true, item_subtype: "entry" });
  await page.goto("/first-times");
  await expect(
    page.getByRole("heading", { name: "Hiking alone" }),
  ).toBeVisible();
  await page.goto("/timeline");
  const firstTimes = page.getByRole("list", { name: "First Times" });
  await expect(
    firstTimes.getByRole("link", { name: /Hiking alone/ }),
  ).toBeVisible();
  await timeline
    .getByTestId("timeline-viewport")
    .evaluate((element) => (element.scrollLeft = element.scrollWidth));
  await page.screenshot({
    animations: "disabled",
    caret: "initial",
    path: test.info().outputPath("memotrail-chapters-timeline-recent.png"),
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({
    animations: "disabled",
    caret: "initial",
    fullPage: true,
    path: test.info().outputPath("memotrail-chapters-timeline-mobile.png"),
  });
  await page.setViewportSize({ width: 1280, height: 720 });

  // Checking Chapter on another Entry makes it a Chapter with a page of its Entries.
  await page.goto(`/items/${abroad.id}`);
  await expect(
    page.getByRole("heading", { name: "In this Chapter" }),
  ).toHaveCount(0);
  await page.getByRole("button", { name: "Edit Entry" }).click();
  const abroadEditor = page.getByRole("dialog", { name: "Edit Entry" });
  await abroadEditor.getByRole("checkbox", { name: /^Chapter/ }).check();
  await abroadEditor.getByLabel("Title", { exact: true }).fill("Study abroad");
  await fillOccurrenceEnd(abroadEditor, "2019-06-01");
  await abroadEditor.getByRole("button", { name: "Save changes" }).click();
  await expect(abroadEditor).not.toBeVisible();
  await expect(
    page.getByRole("heading", { name: "In this Chapter" }),
  ).toBeVisible();
  await expect(
    page
      .getByRole("list", { name: "Entries in this Chapter" })
      .getByRole("listitem")
      .locator("strong"),
  ).toHaveText(["Exam week"]);

  // Unchecking Chapter returns it to an ordinary Entry.
  await page.getByRole("button", { name: "Edit Chapter" }).click();
  const again = page.getByRole("dialog", { name: "Edit Entry" });
  await again.getByRole("checkbox", { name: /^Chapter/ }).uncheck();
  await again.getByRole("button", { name: "Save changes" }).click();
  await expect(again).not.toBeVisible();
  await expect(page.getByRole("button", { name: "Edit Entry" })).toBeVisible();
  await expect(
    page.getByRole("heading", { name: "In this Chapter" }),
  ).toHaveCount(0);
  expect(
    (
      await client
        .from("entries")
        .select("item_subtype")
        .eq("id", abroad.id)
        .single()
    ).data,
  ).toEqual({ item_subtype: "entry" });
  expect(uiErrors).toEqual([]);
});
