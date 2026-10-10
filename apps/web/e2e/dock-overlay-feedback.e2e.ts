import sharp from "sharp";
import { test, expect } from "./helpers/workspace-test";

test("dock feedback stays readable over light and dark content and places Search last", async ({
  page,
  workspace,
}) => {
  expect(workspace.owner).toBeTruthy();
  await page.setViewportSize({ width: 1440, height: 960 });
  await page.goto("/library");
  const capture = page.getByRole("button", { name: "New entry", exact: true });
  const search = page.getByRole("button", {
    name: "Search your trail",
    exact: true,
  });
  await expect(capture).toBeVisible();
  const captureBox = (await capture.boundingBox())!;
  const searchBox = (await search.boundingBox())!;
  expect.soft(captureBox.x + captureBox.width).toBeLessThan(searchBox.x);

  for (const theme of ["light", "dark"] as const) {
    await page.emulateMedia({ colorScheme: theme });
    for (const background of ["#000000", "#ffffff"]) {
      // Scroll past the normal page content onto a solid surface to exercise
      // the extreme backgrounds that can sit beneath this floating glass.
      await page.locator("main").evaluate((element, color) => {
        element.style.backgroundColor = color;
        element.style.minHeight = "220vh";
      }, background);
      await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
      await page.mouse.move(24, 100);
      for (const control of [capture, search]) {
        await control.evaluate((element) =>
          Promise.allSettled(
            element.getAnimations().map((animation) => animation.finished),
          ),
        );
      }
      const png = await page.screenshot({ caret: "initial" });
      const { data, info } = await sharp(png)
        .raw()
        .toBuffer({ resolveWithObject: true });
      for (const control of [capture, search]) {
        const box = (await control.boundingBox())!;
        const position =
          (Math.round(box.y + 8) * info.width +
            Math.round(box.x + box.width / 2)) *
          info.channels;
        const surface = Array.from(data.subarray(position, position + 3));
        const foregrounds = await control.evaluate((element) => {
          const context = document.createElement("canvas").getContext("2d")!;
          return [element, element.querySelector("kbd")!].map((target) => {
            context.clearRect(0, 0, 1, 1);
            context.fillStyle = getComputedStyle(target).color;
            context.fillRect(0, 0, 1, 1);
            return Array.from(context.getImageData(0, 0, 1, 1).data).slice(
              0,
              3,
            );
          });
        });
        for (const foreground of foregrounds) {
          expect
            .soft(
              contrast(foreground, surface),
              `${theme} dock text over ${background}`,
            )
            .toBeGreaterThanOrEqual(4.5);
        }
      }
      for (const control of [capture, search]) {
        const beforeHover = await control.evaluate((element) => {
          const style = getComputedStyle(element);
          return {
            background: style.backgroundColor,
            border: style.borderColor,
          };
        });
        await control.hover();
        await control.evaluate((element) =>
          Promise.allSettled(
            element.getAnimations().map((animation) => animation.finished),
          ),
        );
        await expect
          .soft(control)
          .toHaveCSS("background-color", beforeHover.background);
        await expect
          .soft(control)
          .not.toHaveCSS("border-color", beforeHover.border);
        await page.mouse.move(24, 100);
        await control.evaluate((element) =>
          Promise.allSettled(
            element.getAnimations().map((animation) => animation.finished),
          ),
        );
        await expect(control).toHaveCSS(
          "background-color",
          beforeHover.background,
        );
        await expect(control).toHaveCSS("border-color", beforeHover.border);
      }
    }
  }
});

test("expanded capture shares a glass surface and keeps its save hint inside narrow windows", async ({
  page,
  workspace,
}) => {
  expect(workspace.owner).toBeTruthy();
  await page.setViewportSize({ width: 1440, height: 960 });
  await page.goto("/library");
  const trigger = page.getByRole("button", { name: "New entry", exact: true });
  const dialog = page.getByRole("dialog", { name: "What’s on your mind?" });
  const save = dialog.getByRole("button", {
    name: "Save to Library",
    exact: true,
  });
  const hint = dialog.getByRole("tooltip", {
    name: "Save to Library ⌘ Return",
  });
  for (const theme of ["light", "dark"] as const) {
    await page.emulateMedia({ colorScheme: theme });
    await page.locator("main").evaluate((element) => {
      element.style.backgroundColor = "#000000";
      element.style.minHeight = "220vh";
    });
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await trigger.click();
    await expect(
      dialog.getByRole("textbox", { name: "Entry text" }),
    ).toBeFocused();
    await dialog.evaluate((element) =>
      Promise.allSettled(
        element.getAnimations().map((animation) => animation.finished),
      ),
    );
    const box = (await dialog.boundingBox())!;
    const header = (await dialog.locator("header").boundingBox())!;
    const actions = (await dialog
      .locator("[data-capture-actions]")
      .boundingBox())!;
    const { data, info } = await sharp(
      await page.screenshot({
        path: test
          .info()
          .outputPath(`memotrail-capture-glass-surface-${theme}.png`),
      }),
    )
      .raw()
      .toBuffer({ resolveWithObject: true });
    // Sample blank areas beside the controls on the same solid background.
    // Opaque header/footer overlays would make the panel look like three bands.
    const samples = [
      header.y + header.height / 2,
      header.y + header.height + 24,
      actions.y + actions.height / 2,
    ].map((y) => {
      const position =
        (Math.round(y) * info.width + Math.round(box.x + box.width - 14)) *
        info.channels;
      return Array.from(data.subarray(position, position + 3));
    });
    for (const sample of [samples[0], samples[2]]) {
      expect(
        Math.max(
          ...sample.map((value, channel) =>
            Math.abs(value - samples[1][channel]),
          ),
        ),
        `${theme} header and footer should not add opaque bands: ${JSON.stringify(samples)}`,
      ).toBeLessThanOrEqual(12);
    }
    await page.locator("main").evaluate((element) => {
      element.style.backgroundColor = "";
      element.style.minHeight = "";
    });
    await page.evaluate(() => window.scrollTo(0, 0));
    await save.hover();
    await expect(hint).toBeVisible();
    await page.screenshot({
      animations: "disabled",
      path: test
        .info()
        .outputPath(`memotrail-capture-glass-unified-${theme}.png`),
    });
    await dialog.screenshot({
      animations: "disabled",
      path: test
        .info()
        .outputPath(`memotrail-capture-save-tooltip-${theme}.png`),
    });
    await dialog.getByRole("button", { name: "Close quick capture" }).click();
    await expect(dialog).not.toBeVisible();
  }
  await page.setViewportSize({ width: 320, height: 780 });
  await page.emulateMedia({ colorScheme: "light" });
  await trigger.click();
  await save.hover();
  await expect(hint).toBeVisible();
  const hintBox = (await hint.boundingBox())!;
  const dialogBox = (await dialog.boundingBox())!;
  expect(hintBox.x).toBeGreaterThanOrEqual(dialogBox.x);
  expect(hintBox.x + hintBox.width).toBeLessThanOrEqual(
    dialogBox.x + dialogBox.width,
  );
  expect(hintBox.y).toBeGreaterThanOrEqual(dialogBox.y);
  expect(hintBox.y + hintBox.height).toBeLessThanOrEqual(
    dialogBox.y + dialogBox.height,
  );
  await page.screenshot({
    animations: "disabled",
    path: test.info().outputPath("memotrail-capture-save-tooltip-mobile.png"),
  });
});

function contrast(first: number[], second: number[]) {
  const luminance = (rgb: number[]) =>
    rgb
      .map((value) => {
        const channel = value / 255;
        return channel <= 0.04045
          ? channel / 12.92
          : ((channel + 0.055) / 1.055) ** 2.4;
      })
      .reduce(
        (sum, value, index) => sum + value * [0.2126, 0.7152, 0.0722][index],
        0,
      );
  const a = luminance(first);
  const b = luminance(second);
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}
