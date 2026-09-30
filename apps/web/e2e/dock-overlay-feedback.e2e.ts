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
        const beforeHover = await control.evaluate(
          (element) => getComputedStyle(element).backgroundColor,
        );
        await control.hover();
        await control.evaluate((element) =>
          Promise.allSettled(
            element.getAnimations().map((animation) => animation.finished),
          ),
        );
        await expect
          .soft(control)
          .not.toHaveCSS("background-color", beforeHover);
        await page.mouse.move(24, 100);
        await control.evaluate((element) =>
          Promise.allSettled(
            element.getAnimations().map((animation) => animation.finished),
          ),
        );
        await expect(control).toHaveCSS("background-color", beforeHover);
      }
    }
  }
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
