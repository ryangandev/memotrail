import { expect, test } from "@playwright/test";
import sharp from "sharp";
import {
  expectSeparatorsBetweenWords,
  expectUnclippedFocusRing,
} from "./helpers/separators";

test("selected brand motion previews both panel directions and respects reduced motion", async ({
  page,
}) => {
  const hydrationWarnings: string[] = [];
  page.on("console", (message) => {
    if (/hydration|hydrated/i.test(message.text())) {
      hydrationWarnings.push(message.text());
    }
  });
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto("/design-system#brand-motion");
  const specimen = page.locator("#brand-motion");
  const studies = specimen.locator("[data-brand-motion-study]");
  await expect(studies).toHaveCount(1);
  const counter = specimen.locator('[data-brand-motion-study="counter"]');
  await expect(
    counter.getByRole("heading", { name: "Counter rotation" }),
  ).toBeVisible();
  await specimen.screenshot({
    caret: "initial",
    path: "/private/tmp/memotrail-brand-motion-expanded.png",
  });
  await counter
    .getByRole("button", { name: "Collapse Counter rotation preview" })
    .click();
  for (const part of ["outer-ring", "accent", "inner-ring"]) {
    for (const ring of await counter
      .locator(`[data-brand-part="${part}"]`)
      .all()) {
      await expect(ring).toHaveCSS(
        "transform",
        part === "inner-ring"
          ? "matrix(0, -1, 1, 0, 0, 0)"
          : "matrix(0, 1, -1, 0, 0, 0)",
      );
    }
  }
  await expect(counter).toHaveAttribute("data-collapsed", "true");
  const staticBrand = page.locator("[data-brand-identity] svg");
  for (const part of await staticBrand.locator("path").all()) {
    await expect(part).toHaveCSS("transform", "none");
  }
  await specimen.screenshot({
    caret: "initial",
    path: "/private/tmp/memotrail-brand-motion-collapsed.png",
    animations: "disabled",
  });
  await counter
    .getByRole("button", { name: "Expand Counter rotation preview" })
    .click();
  for (const part of await counter.locator("path").all()) {
    await expect(part).toHaveCSS("transform", "none");
  }
  await page.setViewportSize({ width: 320, height: 740 });
  await page.emulateMedia({ colorScheme: "dark", reducedMotion: "reduce" });
  await counter
    .getByRole("button", { name: "Collapse Counter rotation preview" })
    .click();
  for (const part of await counter.locator("path").all()) {
    await expect(part).toHaveCSS("transition-duration", "0s");
    await expect(part).toHaveCSS("transform", "none");
  }
  await expect(
    specimen.getByText("Reduced motion is on.", { exact: false }),
  ).toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
  await specimen.screenshot({
    caret: "initial",
    path: "/private/tmp/memotrail-brand-motion-mobile.png",
  });
  expect(hydrationWarnings).toEqual([]);
});

test("shared badges keep long labels on one line across sizes", async ({
  page,
}) => {
  await page.goto("/design-system");
  const longBadge = page.getByTitle("A long label that stays on one line");
  await expect(longBadge).toHaveAttribute("data-ui-badge", "true");
  await expect(longBadge).toBeVisible();
  await expect(longBadge).toHaveCSS("white-space", "nowrap");
  await longBadge.evaluate((element) => {
    (element as HTMLElement).style.width = "90px";
  });
  const geometry = await longBadge.evaluate((element) => ({
    height: element.clientHeight,
    scrollHeight: element.scrollHeight,
    width: element.clientWidth,
    scrollWidth: element.scrollWidth,
  }));
  expect(geometry.scrollWidth).toBeGreaterThan(geometry.width);
  expect(geometry.scrollHeight).toBe(geometry.height);
  await expect(longBadge).toHaveCSS("white-space", "nowrap");
  await expect(page.getByTitle("#learning")).toHaveAttribute(
    "data-ui-badge",
    "true",
  );
});

test("SeparatedList keeps its separators between facts as its frame narrows", async ({
  page,
}) => {
  await page.goto("/design-system");
  const specimen = page.locator("#separated-list");
  await specimen.scrollIntoViewIfNeeded();
  for (const width of [1280, 390, 320]) {
    await page.setViewportSize({ width, height: 900 });
    for (const frame of ["wide", "medium", "narrow"]) {
      const lists = specimen.locator(
        `[data-frame="${frame}"] [data-ui-separated-list]`,
      );
      await expect(lists).toHaveCount(3);
      for (const list of await lists.all()) {
        const lines = await expectSeparatorsBetweenWords(list);
        if (frame === "narrow")
          expect(lines.length, JSON.stringify(lines)).toBeGreaterThan(1);
        if (frame === "wide" && width === 1280)
          expect(lines, JSON.stringify(lines)).toHaveLength(1);
        for (const link of await list.getByRole("link").all())
          await expectUnclippedFocusRing(link);
      }
    }
  }
  await specimen.screenshot({
    path: "/private/tmp/memotrail-separated-list-gallery.png",
  });
});

test("Toast uses the shared feedback surface without an inline message", async ({
  page,
}) => {
  await page.goto("/design-system#feedback");
  const feedback = page.locator("#feedback");
  await feedback.getByRole("button", { name: "Show success" }).click();
  const success = page.locator('[data-sonner-toast][data-type="success"]');
  await expect(success).toContainText("Changes saved.");
  await expect(success).toHaveCSS("border-left-width", "3px");
  await success.getByRole("button", { name: "Close toast" }).click();
  await expect(success).toHaveCount(0);
  await feedback.getByRole("button", { name: "Show error" }).click();
  const error = page.locator('[data-sonner-toast][data-type="error"]');
  await expect(error).toContainText("Could not save. Try again.");
  await expect(error).toHaveCSS("border-left-width", "3px");
  await page.setViewportSize({ width: 390, height: 844 });
  await page.emulateMedia({ colorScheme: "dark" });
  const rightEdge = await error.evaluate(
    (element) => element.getBoundingClientRect().right,
  );
  expect(rightEdge).toBeLessThanOrEqual(390);
});

test("Photo field previews existing and selected images without removing them", async ({
  page,
}) => {
  await page.goto("/design-system#forms");
  const specimen = page.locator("article").filter({
    has: page.getByRole("heading", { name: "EntryPhotoField", exact: true }),
  });
  const photos = specimen.locator('[data-entry-photo-field="true"]').first();

  await photos
    .getByRole("button", { name: "Preview coast-memory.jpg" })
    .click();
  const existingPreview = page.getByRole("dialog", {
    name: "coast-memory.jpg",
  });
  await expect(existingPreview).toBeVisible();
  await expect(existingPreview.locator("img")).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(existingPreview).not.toBeVisible();
  await expect(
    photos.getByRole("button", { name: "Preview coast-memory.jpg" }),
  ).toBeFocused();
  await expect(
    photos.getByRole("button", { name: "Remove coast-memory.jpg" }),
  ).toBeVisible();
  await photos.locator('input[type="file"]').setInputFiles({
    name: "new-memory.png",
    mimeType: "image/png",
    buffer: await sharp({
      create: { width: 320, height: 240, channels: 3, background: "#426e83" },
    })
      .png()
      .toBuffer(),
  });
  for (const name of [
    "Remove coast-memory.jpg",
    "Remove selected new-memory.png",
  ]) {
    const iconOffset = await photos
      .getByRole("button", { name })
      .evaluate((button) => {
        const icon = button.querySelector("svg")?.getBoundingClientRect();
        const bounds = button.getBoundingClientRect();
        return icon
          ? Math.hypot(
              icon.x + icon.width / 2 - (bounds.x + bounds.width / 2),
              icon.y + icon.height / 2 - (bounds.y + bounds.height / 2),
            )
          : Infinity;
      });
    expect(iconOffset).toBeLessThan(0.5);
  }
  await photos
    .getByRole("button", { name: "Preview selected new-memory.png" })
    .click();
  const selectedPreview = page.getByRole("dialog", {
    name: "new-memory.png",
  });
  await expect(selectedPreview).toBeVisible();
  await expect
    .poll(() =>
      selectedPreview
        .locator("img")
        .evaluate((img: HTMLImageElement) => img.naturalWidth),
    )
    .toBeGreaterThan(0);
  await selectedPreview.screenshot({
    path: "/private/tmp/memotrail-photo-preview-desktop.png",
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await selectedPreview.screenshot({
    path: "/private/tmp/memotrail-photo-preview-mobile.png",
  });
  await selectedPreview
    .getByRole("button", { name: "Close photo preview" })
    .click();
  await expect(selectedPreview).not.toBeVisible();
  await photos
    .getByRole("button", { name: "Remove selected new-memory.png" })
    .click();
  await expect(
    photos.getByRole("button", { name: "Preview selected new-memory.png" }),
  ).toHaveCount(0);
  await expect(
    photos.getByRole("button", { name: "Remove coast-memory.jpg" }),
  ).toBeVisible();
});

test("OccurrenceEditor keeps the optional date description collapsed", async ({
  page,
}) => {
  await page.goto("/design-system#forms");
  const editor = page.getByRole("group", { name: "Date" });
  await expect(editor).toBeVisible();
  await expect(page.getByText("When it happened")).toHaveCount(0);
  await expect(
    editor.getByRole("textbox", { name: "Date description" }),
  ).toHaveCount(0);
  await editor.getByRole("checkbox", { name: "Add date description" }).check();
  await expect(
    editor.getByRole("textbox", { name: "Date description" }),
  ).toBeVisible();
  await editor
    .getByRole("textbox", { name: "Date description" })
    .fill("Near sunrise");
  await editor
    .getByRole("checkbox", { name: "Add date description" })
    .uncheck();
  await expect(
    editor.getByRole("textbox", { name: "Date description" }),
  ).toHaveCount(0);
});

test("OccurrenceEditor moves between Day, Month, Year, and Not sure without inventing dates", async ({
  page,
}) => {
  const shot = (name: string) =>
    page
      .locator("#forms")
      .getByRole("group", { name: "Date" })
      .screenshot({
        animations: "disabled",
        caret: "initial",
        path: `/private/tmp/memotrail-date-${name}.png`,
      });
  await page.goto("/design-system#forms");
  const editor = page.getByRole("group", { name: "Date" });
  const segment = (name: string) =>
    editor.getByRole("button", { name, exact: true });
  const start = editor.getByRole("textbox", {
    name: /^(Occurred|Start date|Roughly when)$/,
  });
  const toggle = (name: string) =>
    editor.getByRole("checkbox", { name, exact: true });
  await expect(segment("Day")).toHaveAttribute("aria-pressed", "true");
  await expect(start).toHaveValue("2026-09-17");
  await expect(editor.getByRole("combobox", { name: "Time zone" })).toHaveCount(
    0,
  );
  await shot("day");

  // A time is one point in the Settings time zone, so it cannot also end.
  await toggle("Add time").check();
  await expect(editor.getByText("Default from Settings")).toBeVisible();
  await expect(
    editor.getByRole("button", { name: "Choose occurred time" }),
  ).toHaveText("Time");
  await expect(toggle("Add end date")).toHaveCount(0);
  await shot("time");
  await toggle("Add time").uncheck();
  await expect(start).toHaveValue("2026-09-17");

  await toggle("Add end date").check();
  await expect(toggle("Add time")).toHaveCount(0);
  await expect(
    editor.getByRole("textbox", { name: "End date", exact: true }),
  ).toBeVisible();
  await expect(toggle("Present")).not.toBeChecked();
  await shot("range");

  // A coarser date keeps what is known; a finer one starts empty.
  await segment("Month").click();
  await expect(start).toHaveValue("2026-09");
  await expect(toggle("Add end date")).toHaveCount(0);
  await expect(
    editor.getByRole("textbox", { name: "End date", exact: true }),
  ).toHaveCount(0);
  await segment("Year").click();
  await expect(start).toHaveValue("2026");
  await segment("Day").click();
  await expect(start).toHaveValue("");
  await expect(toggle("Add end date")).not.toBeChecked();

  await segment("Not sure").click();
  await expect(segment("Not sure")).toHaveAttribute("aria-pressed", "true");
  await expect(
    editor.getByRole("textbox", { name: "Roughly when" }),
  ).toBeVisible();
  await expect(
    editor.getByRole("textbox", { name: "Date description" }),
  ).toHaveAttribute("required", "");
  await expect(toggle("Add date description")).toHaveCount(0);
  await expect(toggle("Add end date")).not.toBeChecked();
  await shot("not-sure");
  await page.setViewportSize({ width: 390, height: 844 });
  await page.emulateMedia({ colorScheme: "dark" });
  await shot("not-sure-mobile");
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBe(true);
});

test("SearchField has one focus surface and composes with a Search action", async ({
  page,
}) => {
  await page.goto("/design-system#search-field");
  const specimen = page.locator("#search-field");
  const input = specimen.getByRole("searchbox", { name: "Search Locations" });
  await expect(input).toBeVisible();
  await expect(input).toHaveCSS("border-top-width", "0px");
  await input.focus();
  await expect(input).toHaveCSS("box-shadow", "none");
  await expect(input.locator("..")).toHaveCSS("border-top-width", "1px");
  await input.fill("Philadelphia City Hall");
  await specimen.getByRole("button", { name: "Search" }).click();
  await expect(specimen.getByRole("status")).toHaveText(
    "Demo search: Philadelphia City Hall. No request was sent.",
  );
  await expect(
    specimen.getByRole("searchbox", { name: "Disabled search" }),
  ).toBeDisabled();
});

test("TextField previews the shared form typography and focus surface", async ({
  page,
}) => {
  await page.goto("/design-system#text-field");
  const specimen = page.locator("#text-field");
  const input = specimen.getByRole("textbox", { name: "Preferred name" });
  const search = page
    .locator("#search-field")
    .getByRole("searchbox", { name: "Search Locations" });
  const select = page
    .locator("article")
    .filter({
      has: page.getByRole("heading", { name: "SelectField", exact: true }),
    })
    .getByLabel("Show records");

  await expect(input).toHaveValue("Alex Morgan");
  await specimen.screenshot({
    caret: "initial",
    path: "/private/tmp/memotrail-text-field-proposal-light.png",
  });
  const typography = await Promise.all(
    [input, search, select].map((field) =>
      field.evaluate((element) => {
        const style = getComputedStyle(element);
        return {
          family: style.fontFamily,
          size: style.fontSize,
          weight: style.fontWeight,
        };
      }),
    ),
  );
  expect(typography[0]).toEqual(typography[1]);
  expect(typography[0]).toEqual(typography[2]);
  await input.focus();
  await expect(input).toHaveCSS("outline-style", "none");
  await expect(input.locator("..")).toHaveCSS("border-top-width", "1px");
  await input.fill("Alex");
  await expect(input).toHaveValue("Alex");
  await expect(
    specimen.getByRole("textbox", { name: "Disabled text field" }),
  ).toBeDisabled();

  await page.setViewportSize({ width: 390, height: 844 });
  await page.getByLabel("Gallery theme").selectOption("dark");
  await expect(specimen).toBeVisible();
  await specimen.screenshot({
    caret: "initial",
    path: "/private/tmp/memotrail-text-field-proposal-dark-mobile.png",
  });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
});

test("DatePickerField uses the shared form typography", async ({ page }) => {
  await page.goto("/design-system#forms");
  const specimen = page.locator("article").filter({
    has: page.getByRole("heading", { name: "DatePickerField", exact: true }),
  });
  const dateInput = specimen.getByRole("textbox", { name: "Filled date" });
  const textInput = page
    .locator("#text-field")
    .getByRole("textbox", { name: "Preferred name" });
  const textFont = await textInput.evaluate((element) => {
    const style = getComputedStyle(element);
    return { family: style.fontFamily, size: style.fontSize };
  });
  const dateFont = await dateInput.evaluate((element) => {
    const style = getComputedStyle(element);
    return { family: style.fontFamily, size: style.fontSize };
  });
  expect(dateFont).toEqual(textFont);
  await expect(
    specimen.getByRole("button", { name: "Choose exact date and time time" }),
  ).toHaveCSS("font-size", textFont.size);

  await specimen.getByRole("button", { name: "Choose filled date" }).click();
  const calendar = page.locator(
    '[data-scope="date-picker"][data-part="content"][data-state="open"]',
  );
  await expect(calendar).toBeVisible();
  await expect(calendar.locator("th").first()).toHaveCSS("font-size", "12px");
  await expect(
    calendar.locator("[class*=calendarCellTrigger]").first(),
  ).toHaveCSS("font-size", textFont.size);
  await page.keyboard.press("Escape");
  await specimen
    .getByRole("button", { name: "Choose exact date and time time" })
    .click();
  const timePicker = page.locator(
    '[data-scope="popover"][data-part="content"][data-state="open"]',
  );
  await expect(timePicker).toBeVisible();
  await expect(timePicker.getByRole("combobox", { name: "Hour" })).toHaveCSS(
    "font-size",
    textFont.size,
  );
  await expect(timePicker.getByText("Hour", { exact: true })).toHaveCSS(
    "font-size",
    "12px",
  );
});

test("SearchField fits both themes at desktop and mobile widths", async ({
  page,
}) => {
  await page.goto("/design-system#search-field");
  const specimen = page.locator("#search-field");
  for (const [theme, width] of [
    ["light", 1280],
    ["dark", 1280],
    ["light", 390],
    ["dark", 390],
  ] as const) {
    await test.step(`${theme} at ${width}px`, async () => {
      await page.setViewportSize({ width, height: 900 });
      await expect(async () => {
        await page.getByLabel("Gallery theme").selectOption(theme);
        await expect(
          page.locator("[data-theme]").filter({ has: specimen }),
        ).toHaveAttribute("data-theme", theme);
      }).toPass();
      await expect(specimen).toBeVisible();
      await specimen.screenshot({
        animations: "disabled",
        path: `/private/tmp/memotrail-search-field-${theme}-${width}.png`,
      });
      expect(
        await page.evaluate(
          () => document.documentElement.scrollWidth <= window.innerWidth,
        ),
      ).toBe(true);
    });
  }
});

test("Shared primitives support actions, modal focus, nested calendars, and busy submission", async ({
  page,
}) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto("/design-system");
  const review = page.locator("#shared-primitives");
  await review
    .getByRole("button", { name: "Continue", exact: true })
    .first()
    .click();
  await expect(review.getByRole("status")).toHaveText(
    "primary button activated.",
  );
  await expect(
    review.getByRole("button", { name: "Disabled", exact: true }).first(),
  ).toBeDisabled();
  await expect(
    review.getByRole("button", { name: "Saving", exact: true }).first(),
  ).toBeDisabled();
  await review
    .getByRole("button", { name: "Clear filters", exact: true })
    .click();
  await expect(
    review.getByRole("heading", { name: "Filters cleared" }),
  ).toBeVisible();

  const confirmation = review.getByRole("button", {
    name: "Open confirmation",
  });
  await confirmation.click();
  const compact = page.getByRole("dialog", { name: "Remove this memory?" });
  await expect(compact).toBeVisible();
  await compact
    .getByRole("button", { name: "Remove memory", exact: true })
    .focus();
  await page.keyboard.press("Tab");
  await expect(
    compact.getByRole("button", { name: "Close Remove this memory?" }),
  ).toBeFocused();
  await page.keyboard.press("Escape");
  await expect(compact).not.toBeVisible();
  await expect(confirmation).toBeFocused();
  await confirmation.click();
  await expect(compact).toHaveCSS("opacity", "1");
  await page.mouse.click(5, 5);
  await expect(compact).not.toBeVisible();

  await review.getByRole("button", { name: "Open form dialog" }).click();
  const form = page.getByRole("dialog", { name: "Edit a memory" });
  await form.getByRole("button", { name: "Choose memory date" }).click();
  const calendar = page.locator(
    '[data-scope="date-picker"][data-part="content"][data-state="open"]',
  );
  await expect(calendar).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(calendar).not.toBeVisible();
  await expect(form).toBeVisible();
  await form.getByRole("button", { name: "Choose memory date" }).click();
  await calendar.getByRole("button", { name: /September 20, 2026/ }).click();
  await expect(
    form.getByRole("textbox", { name: "Memory date", exact: true }),
  ).toHaveValue("2026-09-20");
  await form.getByRole("button", { name: "Save memory", exact: true }).click();
  await expect(
    form.getByRole("button", { name: "Saving memory" }),
  ).toBeDisabled();
  await expect(
    form.getByRole("button", { name: "Close Edit a memory" }),
  ).toBeDisabled();
  await page.keyboard.press("Escape");
  await expect(form).toBeVisible();
  await expect(form).not.toBeVisible();
  await expect(review.getByRole("status")).toHaveText(
    "Demo saved for 2026-09-20. No data was uploaded.",
  );
  await expect(
    review.getByRole("button", { name: "Open form dialog" }),
  ).toBeFocused();
  expect(errors).toEqual([]);
});

test("Shared primitives fit both themes at desktop and mobile widths", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/design-system");
  for (const theme of ["light", "dark"] as const) {
    for (const width of [1280, 390]) {
      await test.step(`${theme} at ${width}px`, async () => {
        await page.setViewportSize({ width, height: 900 });
        await expect(async () => {
          await page.getByLabel("Gallery theme").selectOption(theme);
          await expect(
            page
              .locator("[data-theme]")
              .filter({ has: page.locator("#shared-primitives") }),
          ).toHaveAttribute("data-theme", theme);
        }).toPass();
        await page.locator("#shared-primitives").screenshot({
          caret: "initial",
          path: `/private/tmp/memotrail-primitives-${theme}-${width}.png`,
        });
        expect(
          await page.evaluate(
            () => document.documentElement.scrollWidth <= window.innerWidth,
          ),
        ).toBe(true);
        await page.getByRole("button", { name: "Open long content" }).click();
        const dialog = page.getByRole("dialog", { name: "A longer story" });
        await expect(dialog).toBeVisible();
        await expect(dialog).toHaveCSS("opacity", "1");
        await expect(dialog).toHaveCSS(
          "background-color",
          theme === "dark" ? "rgb(38, 40, 36)" : "rgb(255, 255, 255)",
        );
        const bounds = await dialog.boundingBox();
        expect(bounds!.x).toBeGreaterThanOrEqual(0);
        expect(bounds!.x + bounds!.width).toBeLessThanOrEqual(width);
        expect(bounds!.y + bounds!.height).toBeLessThanOrEqual(900);
        await expect(
          dialog.getByRole("button", { name: "Done reading" }),
        ).toBeInViewport();
        await page.screenshot({
          caret: "initial",
          path: `/private/tmp/memotrail-dialog-${theme}-${width}.png`,
        });
        await dialog.getByRole("button", { name: "Done reading" }).click();
        await expect(dialog).not.toBeVisible();
      });
    }
  }
});
