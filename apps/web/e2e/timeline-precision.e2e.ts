import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import {
  fillOccurrenceEnd,
  fillOccurrenceStart,
  setDateDescription,
} from "./helpers/occurrence";

test("Timeline edits preserve full occurrence precision without fabricated dates", async ({
  page,
  context,
}) => {
  test.setTimeout(90_000);
  const uiErrors: string[] = [];
  page.on("pageerror", (error) => uiErrors.push(error.message));
  const env = JSON.parse(
    execFileSync("supabase", ["status", "-o", "json"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }),
  );
  expect(env.API_URL).toBe("http://127.0.0.1:54321");
  const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
  const email = `timeline-precision-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  const owner = created.data.user!.id,
    id = randomUUID(),
    ongoingId = randomUUID(),
    vehicleId = randomUUID(),
    firstTimeId = randomUUID();
  try {
    const cookies: { name: string; value: string }[] = [];
    const client = createServerClient(env.API_URL, env.ANON_KEY, {
      cookies: {
        getAll: () => cookies,
        setAll: (values) => {
          cookies.push(
            ...values.map((v) => ({ name: v.name, value: v.value })),
          );
        },
      },
    });
    const link = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    await client.auth.verifyOtp({
      type: "magiclink",
      token_hash: link.data.properties!.hashed_token,
    });
    await context.addCookies(
      cookies.map((c) => ({
        ...c,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax",
        httpOnly: false,
      })),
    );
    const start = "2017-07-08T12:00:00+00:00",
      end = "2017-07-15T12:00:00+00:00";
    expect(
      (
        await client
          .from("profiles")
          .update({
            birth_date: "1990-01-01",
            timezone: "America/New_York",
          })
          .eq("user_id", owner)
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("entries").insert([
          {
            id,
            owner_id: owner,
            title: "First trip to Japan",
            body: "Original travel memory",
            inbox_status: "organized",
            item_kind: "entry",
            item_subtype: "period",
            occurred_start: start,
            occurred_end: end,
            occurred_timezone: "UTC",
            date_precision: "range",
          },
          {
            id: ongoingId,
            owner_id: owner,
            title: "Current role",
            body: "",
            item_kind: "entry",
            item_subtype: "period",
            inbox_status: "organized",
            occurred_start: "2026-04-13T12:00:00+00:00",
            occurred_end: null,
            occurred_timezone: "UTC",
            date_precision: "range",
          },
          {
            id: vehicleId,
            owner_id: owner,
            title: "Centered vehicle",
            body: "",
            item_kind: "entity",
            item_subtype: "vehicle",
            inbox_status: "organized",
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
            item_subtype: "first_time",
            inbox_status: "organized",
            occurred_start: "2026-07-15T12:00:00+00:00",
            occurred_end: null,
            occurred_timezone: "UTC",
            date_precision: "day",
          },
        ])
      ).error,
    ).toBeNull();
    const track = (
      await client
        .from("timeline_tracks")
        .select("id")
        .eq("system_key", "life_stages")
        .single()
    ).data;
    const fallbackTrack =
      track ??
      (await client.from("timeline_tracks").select("id").limit(1).single())
        .data;
    expect(
      (
        await client.from("timeline_items").insert([
          {
            entry_id: id,
            track_id: fallbackTrack!.id,
            owner_id: owner,
            timeline_kind: "stage",
          },
          {
            entry_id: ongoingId,
            track_id: fallbackTrack!.id,
            owner_id: owner,
            timeline_kind: "stage",
          },
          {
            entry_id: vehicleId,
            track_id: fallbackTrack!.id,
            owner_id: owner,
            timeline_kind: "stage",
          },
        ])
      ).error,
    ).toBeNull();
    await page.goto("/library");
    await page.getByRole("link", { name: /First trip to Japan/ }).click();
    await expect(page).toHaveURL(`/timeline?entry=${id}`);
    await expect(page.getByRole("dialog", { name: "First trip to Japan" })).toBeVisible();
    await page.getByRole("button", { name: "Close Timeline editor" }).click();
    await expect(page).toHaveURL(/\/timeline$/);
    const timelineViewport = page.getByTestId("timeline-viewport");
    await expect(timelineViewport).toBeVisible();
    const todayLine = page.getByTestId("timeline-today");
    const ongoingStage = page.getByRole("button", { name: /Current role/ });
    const vehicleStage = page.getByRole("button", {
      name: /Centered vehicle/,
    });
    const firstTimeMarker = page.getByRole("button", {
      name: /First summer visit/,
    });
    await expect(todayLine).toBeVisible();
    await expect(ongoingStage).toHaveAttribute("data-ongoing", "true");
    await expect(vehicleStage).toBeVisible();
    await expect(firstTimeMarker).toBeVisible();
    const firstTimeAlignment = await firstTimeMarker.evaluate((element) => {
      const dot = element.querySelector("span")!.getBoundingClientRect();
      const canvas = element.parentElement!.getBoundingClientRect();
      const anchor = canvas.left + parseFloat(getComputedStyle(element).left);
      return Math.abs(dot.left + dot.width / 2 - anchor);
    });
    expect(firstTimeAlignment).toBeLessThan(1);
    for (const stage of [ongoingStage, vehicleStage]) {
      const appearance = await stage.evaluate((element) => {
        const card = element.getBoundingClientRect();
        const label = element.querySelector("span")!.getBoundingClientRect();
        return {
          centerOffset: Math.abs(
            card.top + card.height / 2 - (label.top + label.height / 2),
          ),
          indicatorContent: window.getComputedStyle(element, "::after").content,
        };
      });
      expect(appearance.centerOffset).toBeLessThan(1);
      expect(appearance.indicatorContent).toBe("none");
    }
    await page.getByRole("button", { name: "Add moment", exact: true }).click();
    const typeChooser = page.getByRole("dialog", {
      name: "What are you adding?",
      exact: true,
    });
    await expect(typeChooser).toBeVisible();
    await expect(
      typeChooser.getByRole("button", { name: "Add Moment", exact: true }),
    ).toBeVisible();
    await expect(
      typeChooser.getByRole("button", { name: "Add Home", exact: true }),
    ).toBeVisible();
    await expect(
      typeChooser.getByRole("button", { name: "Add Vehicle", exact: true }),
    ).toBeVisible();
    await expect(
      typeChooser.getByRole("button", { name: "Add First Time", exact: true }),
    ).toBeVisible();
    await page.setViewportSize({ width: 390, height: 844 });
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-entry-type-chooser-mobile.png",
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);
    await page.setViewportSize({ width: 1280, height: 720 });
    await typeChooser
      .getByRole("button", { name: "Add Moment", exact: true })
      .click();
    const dialog = page.getByRole("dialog");
    await expect(dialog.getByRole("combobox", { name: "Track" })).toBeVisible();
    await dialog.getByRole("button", { name: "Cancel", exact: true }).click();

    await page.getByRole("button", { name: "Add moment", exact: true }).click();
    await typeChooser
      .getByRole("button", { name: "Add Vehicle", exact: true })
      .click();
    const vehicleEditor = page.getByRole("dialog", {
      name: "Keep a Vehicle in your Life Wiki",
      exact: true,
    });
    await expect(vehicleEditor).toBeVisible();
    await expect(page).toHaveURL(/\/timeline$/);
    await expect(
      vehicleEditor.getByRole("combobox", { name: "Track" }),
    ).toHaveCount(0);
    await vehicleEditor
      .getByRole("textbox", { name: "Name or nickname" })
      .fill("Timeline-created vehicle");
    await vehicleEditor
      .getByRole("button", { name: "Add Vehicle", exact: true })
      .click();
    await expect(vehicleEditor).not.toBeVisible();
    await expect
      .poll(async () => {
        const result = await client
          .from("entries")
          .select("item_kind,item_subtype")
          .eq("owner_id", owner)
          .eq("title", "Timeline-created vehicle")
          .maybeSingle();
        return result.data;
      })
      .toEqual({ item_kind: "entity", item_subtype: "vehicle" });
    const createdVehicleCard = page.getByRole("button", {
      name: /Timeline-created vehicle/,
    });
    await expect(createdVehicleCard).toBeVisible();
    await createdVehicleCard.click();
    await expect(
      page.getByRole("dialog", { name: "Timeline-created vehicle" }),
    ).toBeVisible();
    await page
      .getByRole("button", { name: "Close Vehicle editor", exact: true })
      .click();
    await page
      .getByRole("button", { name: "Add a moment to Vehicles", exact: true })
      .click();
    await expect(vehicleEditor).toBeVisible();
    await expect(typeChooser).toHaveCount(0);
    await vehicleEditor
      .getByRole("button", { name: "Cancel", exact: true })
      .click();
    await page
      .getByRole("button", { name: "Add a moment to Homes", exact: true })
      .click();
    const homeEditor = page.getByRole("dialog", {
      name: "Keep a Home in your Life Wiki",
      exact: true,
    });
    await expect(homeEditor).toBeVisible();
    await homeEditor
      .getByRole("button", { name: "Cancel", exact: true })
      .click();
    await page
      .getByRole("button", {
        name: "Add a moment to First Times",
        exact: true,
      })
      .click();
    const firstTimeEditor = page.getByRole("dialog", {
      name: "Keep a beginning",
      exact: true,
    });
    await expect(firstTimeEditor).toBeVisible();
    await firstTimeEditor
      .getByRole("button", { name: "Cancel", exact: true })
      .click();
    const ongoingGeometry = await ongoingStage.evaluate((element) => {
      const card = element.getBoundingClientRect();
      const line = document
        .querySelector('[data-testid="timeline-today"]')!
        .getBoundingClientRect();
      const style = window.getComputedStyle(element);
      return {
        cardRight: card.right,
        lineLeft: line.left,
        rightBorderRadius: style.borderTopRightRadius,
      };
    });
    expect(
      Math.abs(ongoingGeometry.cardRight - ongoingGeometry.lineLeft),
    ).toBeLessThan(1);
    expect(ongoingGeometry.rightBorderRadius).toBe("0px");
    const edgeBounds = await timelineViewport.evaluate((element) => {
      element.scrollLeft = element.scrollWidth;
      const finalYear = element.querySelector(
        '[data-testid="timeline-axis"] span:last-child',
      );
      const viewportBox = element.getBoundingClientRect();
      const finalYearBox = finalYear?.getBoundingClientRect();

      return {
        finalYearRight: finalYearBox?.right ?? 0,
        finalYearWidth: finalYearBox?.width ?? 0,
        viewportRight: viewportBox.right,
        viewportWidth: viewportBox.width,
      };
    });
    expect(edgeBounds.viewportWidth).toBeGreaterThan(0);
    expect(edgeBounds.finalYearWidth).toBeGreaterThan(0);
    expect(edgeBounds.finalYearRight).toBeLessThanOrEqual(
      edgeBounds.viewportRight + 1,
    );
    const timelineStage = page.getByRole("button", {
      name: /First trip to Japan/,
    });
    await timelineStage.click();
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-timeline-precision-desktop.png",
    });
    const startDatePicker = dialog.getByRole("button", {
      name: "Choose start date",
      exact: true,
    });
    await startDatePicker.click();
    await expect(
      page.locator(
        '[data-scope="date-picker"][data-part="content"][data-state="open"]',
      ),
    ).toBeVisible();
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-date-picker-desktop.png",
    });
    await startDatePicker.click();
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-timeline-precision-mobile.png",
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);
    await page.setViewportSize({ width: 1280, height: 720 });
    await page.emulateMedia({ colorScheme: "light" });
    await dialog.getByRole("button", { name: "Save changes" }).click();
    await expect(dialog).not.toBeVisible();
    await expect
      .poll(
        async () =>
          (
            await client
              .from("entries")
              .select("revision")
              .eq("id", id)
              .single()
          ).data?.revision,
      )
      .toBeGreaterThan(1);
    const saved = (
      await client
        .from("entries")
        .select("occurred_start,occurred_end,date_precision")
        .eq("id", id)
        .single()
    ).data!;
    expect(saved.occurred_end).toBe(end);
    expect(saved.occurred_start).toBe(start);
    expect(saved.date_precision).toBe("range");
    // Untouched fractional instants and the second repeated DST hour must survive.
    const revision = (
      await client.from("entries").select("revision").eq("id", id).single()
    ).data!.revision;
    const exact = "2026-11-01T09:30:00.123456+00:00";
    expect(
      (
        await client
          .from("entries")
          .update({
            occurred_start: exact,
            occurred_end: null,
            date_precision: "exact",
            occurred_timezone: "America/Los_Angeles",
            revision: revision + 1,
          })
          .eq("id", id)
      ).error,
    ).toBeNull();
    await page.reload();
    await page.getByRole("button", { name: /First trip to Japan/ }).click();
    await expect(
      dialog.getByRole("combobox", { name: "Date type", exact: true }),
    ).toHaveValue("exact");
    await expect(
      dialog.getByRole("button", {
        name: "Choose start date time",
        exact: true,
      }),
    ).toContainText("01:30");
    const timezone = dialog.getByRole("combobox", {
      name: "Time zone",
      exact: true,
    });
    await expect(timezone).toHaveValue("America/Los_Angeles");
    await expect(
      timezone.locator('option[value="America/Los_Angeles"]'),
    ).toHaveText("(UTC-08:00) Los Angeles - America");
    await expect(
      dialog.getByText("Entry override", { exact: true }),
    ).toBeVisible();
    await expect(
      dialog.getByRole("button", { name: "Change", exact: true }),
    ).toHaveCount(0);
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-exact-datetime-desktop.png",
    });
    await dialog
      .getByRole("button", {
        name: "Choose start date time",
        exact: true,
      })
      .click();
    const timePicker = page.getByRole("dialog", {
      name: "Choose start date time",
      exact: true,
    });
    await expect(
      timePicker.getByRole("combobox", { name: "Hour" }),
    ).toHaveValue("01");
    await expect(
      timePicker.getByRole("combobox", { name: "Minute" }),
    ).toHaveValue("30");
    await expect(
      timePicker.getByRole("combobox", { name: "Second" }),
    ).toHaveCount(0);
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-time-picker-desktop.png",
    });
    await timePicker.getByRole("button", { name: "Done", exact: true }).click();
    await dialog.getByRole("button", { name: "Save changes" }).click();
    await expect(dialog).not.toBeVisible();
    expect(
      (
        await client
          .from("entries")
          .select("occurred_start")
          .eq("id", id)
          .single()
      ).data!.occurred_start,
    ).toBe(exact);
    for (const sample of [
      { precision: "year", start: "2017", label: "", end: "2023" },
      { precision: "month", start: "2017-07", label: "", end: "2023-06" },
      { precision: "day", start: "2017-07-08", label: "", end: "" },
      { precision: "age", start: "", label: "17岁", end: "" },
      {
        precision: "approximate",
        start: "",
        label: "Summer before college",
        end: "",
      },
      { precision: "range", start: "2017-07-08", label: "", end: "2017-07-15" },
      { precision: "unknown", start: "", label: "", end: "" },
    ]) {
      await page.getByRole("button", { name: /First trip to Japan/ }).click();
      await dialog
        .getByRole("combobox", { name: "Date type", exact: true })
        .selectOption(sample.precision);
      if (sample.start) await fillOccurrenceStart(dialog, sample.start);
      if (sample.end) await fillOccurrenceEnd(dialog, sample.end);
      await setDateDescription(dialog, sample.label);
      await dialog.getByRole("button", { name: "Save changes" }).click();
      await expect(dialog).not.toBeVisible();
      const value = (
        await client
          .from("entries")
          .select("date_precision,occurred_start,occurred_end,occurred_label")
          .eq("id", id)
          .single()
      ).data!;
      expect(value.date_precision).toBe(sample.precision);
      if (!sample.start) expect(value.occurred_start).toBeNull();
      if (sample.end) expect(value.occurred_end).not.toBeNull();
    }
    await expect(
      page.getByRole("region", { name: "Without a calendar date" }),
    ).toContainText("First trip to Japan");
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-timeline-undated.png",
    });
    await page.getByRole("button", { name: "Add moment", exact: true }).click();
    await typeChooser
      .getByRole("button", { name: "Add Moment", exact: true })
      .click();
    await dialog.getByRole("button", { name: "Period", exact: true }).click();
    await expect(dialog.getByText("Optional", { exact: true })).toHaveCount(0);
    await dialog.getByLabel("Date type").selectOption("exact");
    const exactStartDate = dialog.getByRole("textbox", {
      name: "Start date",
      exact: true,
    });
    const emptyInputWidth = await exactStartDate.evaluate(
      (input) => input.getBoundingClientRect().width,
    );
    const clearStartDate = dialog.locator(
      'button[aria-label="Clear start date"]',
    );
    await expect(clearStartDate).not.toBeVisible();
    await exactStartDate.fill("20ab17/07-08");
    await expect(exactStartDate).toHaveValue("2017-07-08");
    await expect(exactStartDate).toHaveCSS("border-top-width", "0px");
    await expect(clearStartDate).toBeVisible();
    expect(
      Math.abs(
        (await exactStartDate.evaluate(
          (input) => input.getBoundingClientRect().width,
        )) - emptyInputWidth,
      ),
    ).toBeLessThan(1);
    await clearStartDate.hover();
    await expect(clearStartDate).toHaveCSS(
      "background-color",
      "rgba(0, 0, 0, 0)",
    );
    expect(
      await clearStartDate.evaluate((button) => {
        const buttonRect = button.getBoundingClientRect();
        const iconRect = button.querySelector("svg")!.getBoundingClientRect();
        return Math.abs(
          buttonRect.top +
            buttonRect.height / 2 -
            (iconRect.top + iconRect.height / 2),
        );
      }),
    ).toBeLessThan(1);
    for (const action of [
      dialog.getByRole("button", { name: "Choose start date", exact: true }),
      dialog.getByRole("button", {
        name: "Choose start date time",
        exact: true,
      }),
    ]) {
      await action.hover();
      expect(
        await action.evaluate((button) => {
          const control = button.parentElement!.getBoundingClientRect();
          const actionRect = button.getBoundingClientRect();
          return Math.min(
            actionRect.top - control.top,
            control.bottom - actionRect.bottom,
          );
        }),
      ).toBeGreaterThanOrEqual(4);
    }
    const defaultTimezoneSelect = dialog.getByRole("combobox", {
      name: "Time zone",
      exact: true,
    });
    await expect(defaultTimezoneSelect).toHaveValue("America/New_York");
    await expect(
      defaultTimezoneSelect.locator('option[value="America/New_York"]'),
    ).toHaveText("(UTC-04:00) New York - America");
    await expect(
      dialog.getByText("Default from Settings", { exact: true }),
    ).toBeVisible();
    await dialog.getByLabel("Date type").selectOption("range");
    const present = dialog.getByRole("checkbox", {
      name: "Present",
      exact: true,
    });
    const startDate = dialog.getByRole("textbox", {
      name: "Start date",
      exact: true,
    });
    const startBeforePresent = await startDate.boundingBox();
    await expect(present).not.toBeChecked();
    await expect(
      dialog.getByRole("textbox", { name: "End date", exact: true }),
    ).toBeVisible();
    await present.check();
    await expect(
      dialog.getByRole("textbox", { name: "End date", exact: true }),
    ).toHaveCount(0);
    const startAfterPresent = await startDate.boundingBox();
    expect(startBeforePresent).not.toBeNull();
    expect(startAfterPresent).not.toBeNull();
    expect(
      Math.abs(startBeforePresent!.width - startAfterPresent!.width),
    ).toBeLessThan(2);
    await dialog.getByRole("button", { name: "Cancel", exact: true }).click();
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.getByRole("button", { name: /First trip to Japan/ }).click();
    await expect(dialog.getByLabel("Date type")).toHaveValue("unknown");
    await dialog.getByRole("button", { name: "Cancel", exact: true }).click();
    await page.getByRole("button", { name: "Add moment", exact: true }).click();
    await typeChooser
      .getByRole("button", { name: "Add Moment", exact: true })
      .click();
    await expect(dialog.getByLabel("Date type")).toHaveValue("unknown");
    await dialog.getByRole("button", { name: "Moment", exact: true }).click();
    await expect(
      dialog
        .getByRole("combobox", { name: "Date type", exact: true })
        .locator('option[value="range"]'),
    ).toHaveCount(0);
    await dialog.getByRole("button", { name: "Period", exact: true }).click();
    await dialog.getByLabel("Date type").selectOption("range");
    await expect(
      dialog.getByRole("checkbox", { name: "Present", exact: true }),
    ).not.toBeChecked();
    await expect(
      dialog.getByRole("textbox", { name: "End date", exact: true }),
    ).toBeVisible();
    await expect(
      dialog.getByText("Choose Present when this period is still happening."),
    ).toHaveCount(0);
    await dialog
      .getByRole("checkbox", { name: "Present", exact: true })
      .check();
    await expect(
      dialog.getByRole("textbox", { name: "End date", exact: true }),
    ).toHaveCount(0);
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-present-layout-mobile.png",
    });
    await dialog
      .getByLabel("Title", { exact: true })
      .fill("Unanchored childhood");
    await dialog.getByLabel("Date type").selectOption("age");
    await dialog.getByLabel("Date description").fill("Ages 1 to 12");
    await dialog
      .getByRole("checkbox", { name: "Present", exact: true })
      .check();
    await dialog
      .getByRole("button", { name: "Add moment", exact: true })
      .click();
    await expect(dialog).not.toBeVisible();
    const createdMoment = await client
      .from("entries")
      .select("occurred_start,date_precision")
      .eq("title", "Unanchored childhood")
      .single();
    expect(createdMoment.data).toMatchObject({
      occurred_start: null,
      date_precision: "age",
    });
    await page.goto("/first-times");
    await page
      .getByRole("button", { name: "Add First Time", exact: true })
      .click();
    const focusedFirstTime = page.getByRole("dialog", {
      name: "Keep a beginning",
    });
    await focusedFirstTime
      .getByRole("textbox", { name: "Title" })
      .fill("First snow walk");
    await focusedFirstTime
      .getByRole("combobox", { name: "Date type" })
      .selectOption("day");
    await fillOccurrenceStart(focusedFirstTime, "2024-12-01");
    await focusedFirstTime
      .getByRole("button", { name: "Add First Time" })
      .click();
    await expect(focusedFirstTime).not.toBeVisible();
    const savedFirstTime = await client
      .from("entries")
      .select("id")
      .eq("title", "First snow walk")
      .single();
    expect(savedFirstTime.error).toBeNull();
    const placement = await client
      .from("timeline_items")
      .select("entry_id")
      .eq("entry_id", savedFirstTime.data!.id);
    expect(placement.data).toEqual([]);
    await page.goto("/timeline");
    await expect(
      page.getByRole("button", { name: /First snow walk/ }),
    ).toBeVisible();
    expect(uiErrors).toEqual([]);
  } finally {
    await admin.auth.admin.deleteUser(owner);
  }
});
