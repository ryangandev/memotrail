import { expect, test } from "@playwright/test";
import sharp from "sharp";

test("shared Collection card fits four cards across on desktop", async ({
  page,
}) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto("/design-system#collection-card-concept");
  const specimen = page.locator("#collection-card-concept");
  const cards = specimen.locator("[data-collection-card]");
  await expect(cards).toHaveCount(8);
  await expect(cards.first()).toBeVisible();
  await expect(cards.nth(4)).toBeVisible();
  const boxes = await Promise.all(
    [0, 1, 2, 3, 4].map(async (index) => cards.nth(index).boundingBox()),
  );
  expect(boxes.every(Boolean)).toBe(true);
  expect(boxes.slice(0, 4).map((box) => box!.y)).toEqual([
    boxes[0]!.y,
    boxes[0]!.y,
    boxes[0]!.y,
    boxes[0]!.y,
  ]);
  expect(boxes[4]!.y).toBeGreaterThan(boxes[0]!.y);
  expect(boxes[0]!.height).toBeLessThan(170);
  await cards
    .first()
    .getByRole("button", { name: "Manage Early years" })
    .click();
  await expect(page.locator("[data-sonner-toast]")).toContainText(
    "Manage Early years: preview only.",
  );
  await page
    .locator("[data-sonner-toast]")
    .getByRole("button", { name: "Close toast" })
    .click();
  await expect(page.locator("[data-sonner-toast]")).toHaveCount(0);
  await specimen.screenshot({
    path: "/private/tmp/memotrail-collection-card-concept-desktop.png",
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.emulateMedia({ colorScheme: "dark" });
  await expect(cards.first()).toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth,
    ),
  ).toBe(true);
  await specimen.screenshot({
    path: "/private/tmp/memotrail-collection-card-concept-mobile.png",
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
