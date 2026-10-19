import { randomUUID } from "node:crypto";
import type { Locator, Page } from "@playwright/test";
import sharp from "sharp";
import { expect, test } from "./helpers/workspace-test";
import type { SupabaseClient } from "@supabase/supabase-js";

// Tokyo is nine hours from UTC all year, which shows that a capture's day and
// time are read in the browser's own time zone.
test.use({ timezoneId: "Asia/Tokyo" });

test("the composer dates a capture by a day with an optional time", async ({
  context,
  page,
  workspace,
}) => {
  test.setTimeout(120_000);
  const { capture, date, dateToggle, day, open, save, text } =
    await openCapture(page);

  // Date starts on today and offers a day and an optional time, nothing else.
  await dateToggle.click();
  await expect(dateToggle).toHaveAttribute("aria-pressed", "true");
  await expect(day).toHaveValue(
    new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Tokyo" }).format(
      new Date(),
    ),
  );
  await expect(
    date.getByRole("button", { name: "Choose date time", exact: true }),
  ).toHaveText("Time");
  for (const retired of ["Day", "Month", "Year", "Not sure"])
    await expect(
      capture.getByRole("button", { name: retired, exact: true }),
    ).toHaveCount(0);
  await expect(capture.getByRole("combobox")).toHaveCount(0);
  await expect(capture.getByRole("checkbox")).toHaveCount(0);

  // The calendar opens above the short dialog instead of being clipped by it.
  await date.getByRole("button", { name: "Choose date", exact: true }).click();
  const calendar = page.locator(
    '[data-scope="date-picker"][data-part="content"][data-state="open"]',
  );
  await expect(calendar).toBeVisible();
  expect(
    await calendar.evaluate((element) => {
      const header = element
        .querySelector('[data-part="view-control"]')!
        .getBoundingClientRect();
      return element.contains(
        document.elementFromPoint(
          header.x + header.width / 2,
          header.y + header.height / 2,
        ),
      );
    }),
  ).toBe(true);
  await calendar
    .locator('[data-part="table-cell-trigger"]', { hasText: /^15$/ })
    .click();
  await expect(calendar).toHaveCount(0);
  await expect(day).toHaveValue(/-15$/);

  // An unfinished day survives a reload and is refused at Save.
  await text.fill("Back-dated day");
  await day.fill("2017-0");
  await expect
    .poll(() => storedDraft(page, workspace.owner))
    .toMatchObject({
      body: "Back-dated day",
      occurrence: { precision: "day", start: "2017-0" },
    });
  await page.reload();
  await open();
  await expect(day).toHaveValue("2017-0");
  await save.click();
  await expect(capture).toContainText("Choose a valid calendar date");
  expect(await entries(workspace.client)).toHaveLength(0);

  // A day saves at midday in the browser's time zone.
  await day.fill("2017-07-08");
  await save.click();
  await expect(text).toBeEmpty();
  await expect(date).toHaveCount(0);
  await expect
    .poll(() => entries(workspace.client))
    .toEqual([
      expect.objectContaining({
        body: "Back-dated day",
        date_precision: "day",
        occurred_start: "2017-07-08T03:00:00+00:00",
        occurred_timezone: "Asia/Tokyo",
      }),
    ]);

  // A time makes the date exact, and the offline queue keeps it until replay.
  await dateToggle.click();
  await text.fill("Back-dated time");
  await day.fill("2017-07-08");
  await chooseTime(page, date, "12", "34");
  await expect(day).toHaveValue("2017-07-08");
  await page.waitForLoadState("networkidle");
  await context.setOffline(true);
  await save.click();
  await expect(
    capture.getByRole("heading", { name: "Pending sync", exact: true }),
  ).toBeVisible();
  expect(await queuedCaptures(page, workspace.owner)).toEqual([
    expect.objectContaining({
      version: 3,
      datePrecision: "exact",
      occurredAt: "2017-07-08T03:34:00.000Z",
      occurredEnd: null,
      occurredLabel: null,
      occurredTimezone: "Asia/Tokyo",
    }),
  ]);
  await context.setOffline(false);
  await expect
    .poll(async () =>
      (await entries(workspace.client)).find(
        (entry) => entry.body === "Back-dated time",
      ),
    )
    .toMatchObject({
      date_precision: "exact",
      occurred_start: "2017-07-08T03:34:00+00:00",
    });

  // Turning Date off again saves the capture time, and an online save never
  // surfaces the pending list while it waits on MemoTrail.
  await expect(
    capture.getByRole("heading", { name: "Pending sync", exact: true }),
  ).toHaveCount(0);
  await dateToggle.click();
  await expect(date).toBeVisible();
  await dateToggle.click();
  await expect(date).toHaveCount(0);
  await expect(dateToggle).toHaveAttribute("aria-pressed", "false");
  await text.fill("Default capture time");
  await watchPendingSyncSurfaces(page);
  let delayedSync = false;
  await page.route("**/*", async (route) => {
    if (
      !delayedSync &&
      route.request().method() === "POST" &&
      route.request().headers()["next-action"]
    ) {
      delayedSync = true;
      await new Promise((resolve) => setTimeout(resolve, 750));
    }
    await route.continue();
  });
  const beforeDefault = Date.now();
  await save.click();
  await expect(
    capture.getByRole("button", { name: "Saving…", exact: true }),
  ).toBeDisabled();
  await expect
    .poll(async () =>
      (await entries(workspace.client)).find(
        (entry) => entry.body === "Default capture time",
      ),
    )
    .toMatchObject({
      date_precision: "exact",
      occurred_end: null,
      occurred_label: null,
      title: null,
    });
  const defaultEntry = (await entries(workspace.client)).find(
    (entry) => entry.body === "Default capture time",
  )!;
  expect(Date.parse(defaultEntry.occurred_start)).toBeGreaterThanOrEqual(
    beforeDefault,
  );
  expect(Date.parse(defaultEntry.occurred_start)).toBeLessThanOrEqual(
    Date.now(),
  );
  expect(delayedSync).toBe(true);
  expect(
    await page.evaluate(() => sessionStorage.getItem("pending-sync-seen")),
  ).toBe("no");
  await page.unroute("**/*");
  await expect(save).toBeEnabled();
});

test("drafts and queued captures from earlier composers still load", async ({
  page,
  workspace,
}) => {
  test.setTimeout(120_000);
  const { date, day, open, save, text } = await openCapture(page);

  // An earlier composer kept a date range; the composer shows and saves its day.
  await page.evaluate((owner) => {
    localStorage.setItem(
      `memotrail:inbox-draft:${owner}`,
      JSON.stringify({
        version: 3,
        title: "",
        body: "Draft from an earlier composer",
        occurredAt: null,
        updatedAt: new Date().toISOString(),
        occurrence: {
          precision: "range",
          start: "2017-07-01",
          end: "2017-08-12",
          endMode: "date",
          label: "",
          timezone: "Asia/Tokyo",
        },
      }),
    );
  }, workspace.owner);
  await page.reload();
  await open();
  await expect(text).toHaveText("Draft from an earlier composer");
  await expect(day).toHaveValue("2017-07-01");
  await save.click();
  await expect(date).toHaveCount(0);
  await expect
    .poll(() => entries(workspace.client))
    .toEqual([
      expect.objectContaining({
        body: "Draft from an earlier composer",
        date_precision: "day",
        occurred_start: "2017-07-01T03:00:00+00:00",
        occurred_end: null,
      }),
    ]);

  // Old pending payloads keep their UUID and date and are not duplicated on replay.
  const legacyId = randomUUID();
  await page.evaluate(
    ({ owner, legacyId }) => {
      localStorage.setItem(
        `memotrail:inbox-queue:${owner}`,
        JSON.stringify([
          {
            version: 1,
            id: legacyId,
            title: "Legacy capture",
            body: "Older client",
            occurredAt: "2017-07-08T12:34:56.123456Z",
            occurredTimezone: "UTC",
            queuedAt: "2026-09-01T00:00:00Z",
          },
        ]),
      );
    },
    { owner: workspace.owner, legacyId },
  );
  await page.reload();
  await expect
    .poll(async () =>
      (await entries(workspace.client)).find((entry) => entry.id === legacyId),
    )
    .toMatchObject({
      date_precision: "exact",
      occurred_start: "2017-07-08T12:34:56.123456+00:00",
    });
  await expect.poll(() => queuedCaptures(page, workspace.owner)).toEqual([]);
});

test("a draft photo previews in place and removes from its own control", async ({
  page,
  workspace,
}) => {
  expect(workspace.owner).toBeTruthy();
  // The Dashboard composer, since a preview opened from Quick Capture stays
  // under its native dialog.
  await page.goto("/");
  const capture = page.getByRole("form", {
    name: "Quick capture",
    exact: true,
  });
  // The editor mounts only after hydration; a photo chosen before it is ignored.
  await expect(
    capture.getByRole("textbox", { name: "Entry text", exact: true }),
  ).toBeVisible({ timeout: 30_000 });
  await capture.locator('input[type="file"]').setInputFiles({
    name: "quick-preview.png",
    mimeType: "image/png",
    buffer: await sharp({
      create: { width: 320, height: 240, channels: 3, background: "#426e83" },
    })
      .png()
      .toBuffer(),
  });
  const removePhoto = capture.getByRole("button", {
    name: "Remove selected quick-preview.png",
  });
  const removeIconOffset = await removePhoto.evaluate((button) => {
    const icon = button.querySelector("svg")?.getBoundingClientRect();
    const bounds = button.getBoundingClientRect();
    return icon
      ? Math.hypot(
          icon.x + icon.width / 2 - (bounds.x + bounds.width / 2),
          icon.y + icon.height / 2 - (bounds.y + bounds.height / 2),
        )
      : Infinity;
  });
  expect(removeIconOffset).toBeLessThan(0.5);
  await capture
    .getByRole("button", { name: "Preview selected quick-preview.png" })
    .click();
  const photoPreview = page.getByRole("dialog", { name: "quick-preview.png" });
  await expect(photoPreview).toBeVisible();
  await photoPreview
    .getByRole("button", { name: "Close", exact: true })
    .click();
  await removePhoto.click();
  await expect(
    capture.getByRole("button", { name: "Preview selected quick-preview.png" }),
  ).toHaveCount(0);
});

/** Opens Quick Capture from the dock on Library, away from the Dashboard composer. */
async function openCapture(page: Page) {
  await page.goto("/library");
  const capture = page.getByRole("dialog", { name: "What’s on your mind?" });
  const text = capture.getByRole("textbox", {
    name: "Entry text",
    exact: true,
  });
  const date = capture.getByRole("group", { name: "Date", exact: true });
  async function open() {
    await page.getByRole("button", { name: "New entry", exact: true }).click();
    // The editor mounts only after hydration; input before it would be lost.
    await expect(text).toBeVisible({ timeout: 30_000 });
  }
  await open();
  return {
    capture,
    date,
    // The chip says Today or the chosen day, so it is found by its marker.
    dateToggle: capture.locator("[data-capture-date-toggle]"),
    day: date.getByRole("textbox", { name: "Date", exact: true }),
    open,
    save: capture.getByRole("button", { name: "Save", exact: true }),
    text,
  };
}

async function chooseTime(
  page: Page,
  date: Locator,
  hour: string,
  minute: string,
) {
  const title = "Choose date time";
  await date.getByRole("button", { name: title, exact: true }).click();
  const picker = page.getByRole("dialog", { name: title, exact: true });
  await picker.getByRole("combobox", { name: "Hour" }).selectOption(hour);
  await picker.getByRole("combobox", { name: "Minute" }).selectOption(minute);
  await picker.getByRole("button", { name: "Done", exact: true }).click();
  await expect(
    date.getByRole("button", { name: title, exact: true }),
  ).toHaveText(`${hour}:${minute}`);
}

async function entries(client: SupabaseClient) {
  const result = await client
    .from("entries")
    .select(
      "id,body,title,date_precision,occurred_start,occurred_end,occurred_label,occurred_timezone",
    );
  expect(result.error).toBeNull();
  return result.data!;
}

function storedDraft(page: Page, owner: string) {
  return page.evaluate((owner) => {
    const stored = localStorage.getItem(`memotrail:inbox-draft:${owner}`);
    return stored ? JSON.parse(stored) : null;
  }, owner);
}

function queuedCaptures(page: Page, owner: string) {
  return page.evaluate((owner) => {
    const stored = localStorage.getItem(`memotrail:inbox-queue:${owner}`);
    return stored ? JSON.parse(stored) : [];
  }, owner);
}

// Records whether any pending list or the pending sync indicator appears,
// because an online save's first attempt must not surface either.
async function watchPendingSyncSurfaces(page: Page) {
  await page.evaluate(() => {
    sessionStorage.setItem("pending-sync-seen", "no");
    new MutationObserver(() => {
      const listed = [...document.querySelectorAll("h2")].some(
        (heading) => heading.textContent === "Pending sync",
      );
      const indicated = [
        ...document.querySelectorAll("[data-ui-sync-status]"),
      ].some((button) => /^\d+ pending$/.test(button.textContent ?? ""));
      if (listed || indicated) {
        sessionStorage.setItem("pending-sync-seen", "yes");
      }
    }).observe(document.body, {
      characterData: true,
      childList: true,
      subtree: true,
    });
  });
}
