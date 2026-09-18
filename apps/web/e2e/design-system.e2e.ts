import { expect, test } from "@playwright/test";

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

for (const theme of ["light", "dark"] as const) {
  for (const width of [1280, 390]) {
    test(`Shared primitives fit ${theme} at ${width}px`, async ({ page }) => {
      await page.setViewportSize({ width, height: 900 });
      await page.emulateMedia({ reducedMotion: "reduce" });
      await page.goto("/design-system");
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
