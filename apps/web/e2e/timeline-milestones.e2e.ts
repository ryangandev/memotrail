import { randomUUID } from "node:crypto";
import type { Page } from "@playwright/test";
import { expect, test } from "./helpers/workspace-test";
import {
  fillOccurrenceStart,
  setOccurrencePrecision,
} from "./helpers/occurrence";

async function expectNoHorizontalScroll(page: Page) {
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBe(true);
}

test("Timeline shows Homes, Vehicles, and milestones in fixed lanes", async ({
  page,
  workspace: { client, owner },
}) => {
  test.setTimeout(120_000);
  const uiErrors: string[] = [];
  page.on("pageerror", (error) => uiErrors.push(error.message));
  const universityId = randomUUID(),
    roleId = randomUUID(),
    vehicleId = randomUUID(),
    firstTimeId = randomUUID(),
    plainId = randomUUID();
  expect(
    (
      await client
        .from("profiles")
        .update({ birth_date: "1990-01-01", timezone: "America/New_York" })
        .eq("user_id", owner)
    ).error,
  ).toBeNull();
  expect(
    (
      await client.from("entries").insert([
        {
          id: universityId,
          owner_id: owner,
          title: "University",
          body: "",
          item_kind: "entry",
          item_subtype: "entry",
          occurred_start: "2008-09-01T12:00:00+00:00",
          occurred_end: "2012-06-01T12:00:00+00:00",
          occurred_timezone: "UTC",
          date_precision: "range",
        },
        {
          id: roleId,
          owner_id: owner,
          title: "Current role",
          body: "",
          item_kind: "entry",
          item_subtype: "entry",
          occurred_start: "2026-04-13T12:00:00+00:00",
          occurred_end: null,
          occurred_timezone: "UTC",
          date_precision: "day",
        },
        {
          id: vehicleId,
          owner_id: owner,
          title: "Centered vehicle",
          body: "",
          item_kind: "entity",
          item_subtype: "vehicle",
          occurred_start: "2024-01-01T12:00:00+00:00",
          occurred_end: "2025-01-01T12:00:00+00:00",
          occurred_timezone: "UTC",
          date_precision: "range",
        },
        {
          id: firstTimeId,
          owner_id: owner,
          title: "First summer visit",
          body: "",
          item_kind: "entry",
          item_subtype: "entry",
          occurred_start: "2026-07-15T12:00:00+00:00",
          occurred_end: null,
          occurred_timezone: "UTC",
          date_precision: "day",
        },
        {
          id: plainId,
          owner_id: owner,
          title: "A plain note",
          body: "Not a milestone",
          item_kind: "entry",
          item_subtype: "entry",
          occurred_start: "2026-01-01T12:00:00+00:00",
          occurred_end: null,
          occurred_timezone: "UTC",
          date_precision: "day",
        },
      ])
    ).error,
  ).toBeNull();
  expect(
    (
      await client.from("milestones").insert([
        {
          entry_id: universityId,
          owner_id: owner,
          shape: "period",
          lane: "work_study",
          is_first_time: false,
        },
        {
          entry_id: roleId,
          owner_id: owner,
          shape: "period",
          lane: "work_study",
          is_first_time: false,
        },
        {
          entry_id: firstTimeId,
          owner_id: owner,
          shape: "moment",
          lane: "other",
          is_first_time: true,
        },
      ])
    ).error,
  ).toBeNull();

  await page.goto("/timeline");
  const timeline = page.getByRole("region", { name: "Timeline by lane" });
  await expect(timeline).toBeVisible();
  const lanes = timeline.getByTestId("timeline-viewport").locator("strong");
  await expect(lanes).toHaveText([
    "Places lived",
    "Vehicles",
    "Work and study",
    "Other milestones",
  ]);
  await expect(page.getByRole("link", { name: /A plain note/ })).toHaveCount(0);
  await expect(page.getByRole("link", { name: "Manage tracks" })).toHaveCount(
    0,
  );

  // Moments sit on their date, Periods span theirs, and an ongoing Period runs to today.
  const todayLine = timeline.getByTestId("timeline-today");
  const ongoingPeriod = timeline.getByRole("link", { name: /Current role/ });
  const vehiclePeriod = timeline.getByRole("link", {
    name: /Centered vehicle/,
  });
  const firstTimeMarker = timeline.getByRole("link", {
    name: /First summer visit/,
  });
  await expect(todayLine).toBeVisible();
  await expect(ongoingPeriod).toHaveAttribute("data-ongoing", "true");
  await expect(vehiclePeriod).toBeVisible();
  await expect(firstTimeMarker).toBeVisible();
  expect(
    await firstTimeMarker.evaluate((element) => {
      const dot = element.querySelector("span")!.getBoundingClientRect();
      const canvas = element.parentElement!.getBoundingClientRect();
      const anchor = canvas.left + parseFloat(getComputedStyle(element).left);
      return Math.abs(dot.left + dot.width / 2 - anchor);
    }),
  ).toBeLessThan(1);
  for (const period of [ongoingPeriod, vehiclePeriod]) {
    const appearance = await period.evaluate((element) => {
      const card = element.getBoundingClientRect();
      const label = element
        .querySelector("span:last-child")!
        .getBoundingClientRect();
      return {
        centerOffset: Math.abs(
          card.top + card.height / 2 - (label.top + label.height / 2),
        ),
        indicatorContent: window.getComputedStyle(element, "::after").content,
        textDecoration: window.getComputedStyle(element).textDecorationLine,
      };
    });
    expect(appearance.centerOffset).toBeLessThan(1);
    expect(appearance.indicatorContent).toBe("none");
    expect(appearance.textDecoration).toBe("none");
  }
  // A Period too short for its title draws its bar alone and puts the title beside it.
  await expect(ongoingPeriod).toHaveAttribute("data-label", "after");
  await expect(vehiclePeriod).toHaveAttribute("data-label", "inside");
  const ongoingGeometry = await ongoingPeriod.evaluate((element) => {
    const bar = element.querySelector("span:first-child")!;
    const card = bar.getBoundingClientRect();
    const label = element
      .querySelector("span:last-child")!
      .getBoundingClientRect();
    const line = document
      .querySelector('[data-testid="timeline-today"]')!
      .getBoundingClientRect();
    return {
      cardRight: card.right,
      labelLeft: label.left,
      lineLeft: line.left,
      rightBorderRadius: window.getComputedStyle(bar).borderTopRightRadius,
    };
  });
  expect(ongoingGeometry.labelLeft).toBeGreaterThan(ongoingGeometry.cardRight);
  expect(
    Math.abs(ongoingGeometry.cardRight - ongoingGeometry.lineLeft),
  ).toBeLessThan(1);
  expect(ongoingGeometry.rightBorderRadius).toBe("0px");
  // Every title shows in full.
  const truncated = await timeline
    .getByTestId("timeline-viewport")
    .locator("a > span:last-child")
    .evaluateAll((labels) =>
      labels
        .filter((label) => label.scrollWidth > label.clientWidth)
        .map((label) => label.textContent),
    );
  expect(truncated).toEqual([]);
  // Periods in one lane that do not overlap share a row.
  const university = timeline.getByRole("link", { name: /University/ });
  const rows = await Promise.all(
    [university, ongoingPeriod].map((item) =>
      item.evaluate((element) => element.getBoundingClientRect().top),
    ),
  );
  expect(rows[0]).toBe(rows[1]);
  const edgeBounds = await timeline
    .getByTestId("timeline-viewport")
    .evaluate((element) => {
      element.scrollLeft = element.scrollWidth;
      const finalYear = element
        .querySelector('[data-testid="timeline-axis"] span:last-child')!
        .getBoundingClientRect();
      return {
        finalYearRight: finalYear.right,
        viewportRight: element.getBoundingClientRect().right,
      };
    });
  expect(edgeBounds.finalYearRight).toBeLessThanOrEqual(
    edgeBounds.viewportRight + 1,
  );
  await page.screenshot({
    animations: "disabled",
    caret: "initial",
    path: test.info().outputPath("memotrail-timeline-lanes-desktop.png"),
  });

  // A milestone opens as its Entry, and a Vehicle opens as a Vehicle.
  await ongoingPeriod.click();
  await expect(page).toHaveURL(`/items/${roleId}`);
  await expect(page.getByText("Period · Work and study")).toBeVisible();
  await page.goBack();
  await vehiclePeriod.click();
  await expect(page).toHaveURL(`/vehicles/${vehicleId}`);
  await page.goto("/timeline");

  // The chooser offers what can go on Timeline. Each lane adds its own kind.
  await page.getByRole("button", { name: "Add to Timeline" }).first().click();
  const chooser = page.getByRole("dialog", { name: "What are you adding?" });
  for (const name of [
    "Add Milestone",
    "Add First Time",
    "Add Home",
    "Add Vehicle",
  ])
    await expect(
      chooser.getByRole("button", { name, exact: true }),
    ).toBeVisible();
  await page.setViewportSize({ width: 390, height: 844 });
  await expectNoHorizontalScroll(page);
  await page.setViewportSize({ width: 1280, height: 720 });
  await chooser.getByRole("button", { name: "Close Timeline chooser" }).click();
  await page.getByRole("button", { name: "Add a Vehicle" }).click();
  const vehicleEditor = page.getByRole("dialog", {
    name: "Keep a Vehicle in your Life Wiki",
  });
  await expect(vehicleEditor).toBeVisible();
  await vehicleEditor.getByRole("button", { name: "Cancel" }).click();
  await page.getByRole("button", { name: "Add a Home" }).click();
  const homeEditor = page.getByRole("dialog", {
    name: "Keep a Home in your Life Wiki",
  });
  await expect(homeEditor).toBeVisible();
  await homeEditor.getByRole("button", { name: "Cancel" }).click();

  // Adding to Work and study starts a Period in that lane, dated in the Settings time zone.
  await page
    .getByRole("button", { name: "Add a milestone to Work and study" })
    .click();
  const editor = page.getByRole("dialog", { name: "Add a milestone" });
  await expect(editor).toBeVisible();
  await expect(
    editor.getByRole("checkbox", { name: /Show on Timeline/ }),
  ).toBeChecked();
  await expect(
    editor.getByRole("button", { name: "Period", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await expect(editor.getByRole("combobox", { name: "Lane" })).toHaveValue(
    "work_study",
  );
  await setOccurrencePrecision(editor, "exact");
  await expect(editor.getByRole("combobox", { name: "Time zone" })).toHaveValue(
    "America/New_York",
  );
  await expect(editor.getByText("Default from Settings")).toBeVisible();
  // A Moment is one point in time, so it cannot have an end date.
  await editor.getByRole("button", { name: "Moment", exact: true }).click();
  await setOccurrencePrecision(editor, "day");
  for (const name of ["Add end date", "Present"])
    await expect(
      editor.getByRole("checkbox", { name, exact: true }),
    ).toHaveCount(0);
  await expect(
    editor.getByRole("textbox", { name: "End date", exact: true }),
  ).toHaveCount(0);
  await editor.getByRole("button", { name: "Period", exact: true }).click();
  await editor.getByLabel("Title", { exact: true }).fill("Bakery job");
  await fillOccurrenceStart(editor, "2021-03-01");
  await editor.getByRole("checkbox", { name: "Present", exact: true }).check();
  await expect(
    editor.getByRole("textbox", { name: "End date", exact: true }),
  ).toHaveCount(0);
  await page.screenshot({
    animations: "disabled",
    caret: "initial",
    path: test.info().outputPath("memotrail-milestone-editor-desktop.png"),
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.emulateMedia({ colorScheme: "dark" });
  await page.screenshot({
    animations: "disabled",
    caret: "initial",
    path: test.info().outputPath("memotrail-milestone-editor-mobile.png"),
  });
  await expectNoHorizontalScroll(page);
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.emulateMedia({ colorScheme: "light" });
  await editor.getByRole("button", { name: "Add", exact: true }).click();
  await expect(editor).not.toBeVisible();
  await expect(page.getByText("Added to Timeline.")).toBeVisible();
  const bakery = await client
    .from("entries")
    .select("id,item_kind,item_subtype,occurred_end,milestones(shape,lane)")
    .eq("title", "Bakery job")
    .single();
  expect(bakery.data).toMatchObject({
    item_kind: "entry",
    item_subtype: "entry",
    occurred_end: null,
    milestones: [{ shape: "period", lane: "work_study" }],
  });
  await expect(
    timeline.getByRole("link", { name: /Bakery job/ }),
  ).toHaveAttribute("data-ongoing", "true");

  // The phone layout lists each lane with its items.
  await page.setViewportSize({ width: 390, height: 844 });
  await page.emulateMedia({ colorScheme: "dark" });
  const phoneLanes = page.getByRole("region", { name: "Timeline by lane" });
  await expect(
    phoneLanes.getByRole("heading", { name: "Work and study" }),
  ).toBeVisible();
  await expect(
    phoneLanes.getByRole("link", { name: /Bakery job/ }),
  ).toBeVisible();
  await page.screenshot({
    animations: "disabled",
    caret: "initial",
    fullPage: true,
    path: test.info().outputPath("memotrail-timeline-lanes-mobile.png"),
  });
  await expectNoHorizontalScroll(page);
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.emulateMedia({ colorScheme: "light" });

  // Dashboard Now lists what is still going on, newest first within each lane.
  await page.goto("/");
  const now = page.getByRole("region", { name: "Now" });
  await expect(now.getByRole("link", { name: /Work and study/ })).toHaveText([
    "Work and studyCurrent roleSince Apr 13, 2026",
    "Work and studyBakery jobSince Mar 1, 2021",
  ]);
  await expect(
    page.getByRole("link", { name: /2\s*Going on now/ }),
  ).toBeVisible();
  await now.getByRole("link", { name: /Bakery job/ }).click();
  await expect(page).toHaveURL(`/items/${bakery.data!.id}`);
  await expect(
    page.getByRole("heading", { level: 1, name: "Bakery job" }),
  ).toBeVisible();
  expect(uiErrors).toEqual([]);
});

test("A First Time is a milestone that First Times lists and the Entry editor changes", async ({
  page,
  workspace: { client },
}) => {
  test.setTimeout(90_000);
  const uiErrors: string[] = [];
  page.on("pageerror", (error) => uiErrors.push(error.message));
  await page.goto("/first-times");
  await page.getByRole("button", { name: "Add First Time" }).first().click();
  const editor = page.getByRole("dialog", { name: "Add a First Time" });
  await expect(editor).toBeVisible();
  await expect(
    editor.getByRole("checkbox", { name: /First Time/ }),
  ).toBeChecked();
  await expect(
    editor.getByRole("button", { name: "Moment", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await editor.getByLabel("Title", { exact: true }).fill("First snow walk");
  await setOccurrencePrecision(editor, "day");
  await fillOccurrenceStart(editor, "2024-12-01");
  await editor.getByRole("button", { name: "Add", exact: true }).click();
  await expect(editor).not.toBeVisible();
  await expect(page.getByText("First Time added.")).toBeVisible();
  const card = page.getByRole("button", { name: /First snow walk/ });
  await expect(card).toBeVisible();
  const saved = await client
    .from("entries")
    .select("id,milestones(shape,lane,is_first_time)")
    .eq("title", "First snow walk")
    .single();
  expect(saved.data!.milestones).toEqual([
    { shape: "moment", lane: "other", is_first_time: true },
  ]);
  const id = saved.data!.id;

  // It opens as its Entry, where photos and edits live. The old address still works.
  await card.click();
  await expect(page).toHaveURL(`/items/${id}`);
  await expect(
    page.getByText("First Time · Moment · Other milestones"),
  ).toBeVisible();
  await page.goto(`/first-times/${id}`);
  await expect(page).toHaveURL(`/items/${id}`);
  await page.goto("/timeline");
  await expect(
    page
      .getByRole("region", { name: "Timeline by lane" })
      .first()
      .getByRole("link", { name: /First snow walk/ }),
  ).toBeVisible();

  // Taking it off Timeline keeps the Entry but removes it from First Times.
  await page.goto(`/items/${id}`);
  await page.getByRole("button", { name: "Edit Entry" }).click();
  const edit = page.getByRole("dialog", { name: "Edit Entry" });
  await expect(
    edit.getByRole("checkbox", { name: /First Time/ }),
  ).toBeChecked();
  await edit.getByRole("checkbox", { name: /Show on Timeline/ }).uncheck();
  await edit.getByRole("button", { name: "Save changes" }).click();
  await expect(edit).not.toBeVisible();
  await expect
    .poll(
      async () =>
        (await client.from("milestones").select("entry_id").eq("entry_id", id))
          .data,
    )
    .toEqual([]);
  await page.goto("/first-times");
  await expect(
    page.getByRole("heading", { level: 1, name: "First Times" }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: /First snow walk/ }),
  ).toHaveCount(0);
  expect(
    (await client.from("entries").select("id").eq("id", id).single()).data,
  ).toEqual({ id });
  expect(uiErrors).toEqual([]);
});
