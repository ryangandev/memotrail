import { expect, test } from "@playwright/test";

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
