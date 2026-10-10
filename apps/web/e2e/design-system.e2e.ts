import { expect, test } from "@playwright/test";
import sharp from "sharp";
import { componentSpecimens } from "../src/generated/design-system";
import tokens from "../src/generated/design-tokens.json";
import {
  expectSeparatorsBetweenWords,
  expectUnclippedFocusRing,
} from "./helpers/separators";

/** Flattens nested token groups into dotted names, as the gallery labels them. */
function leaves(group: object, prefix = ""): [string, string | number][] {
  return Object.entries(group).flatMap(([key, value]) =>
    value !== null && typeof value === "object"
      ? leaves(value, `${prefix}${key}.`)
      : [[`${prefix}${key}`, value] as [string, string | number]],
  );
}

/** Converts a catalog color to the form getComputedStyle reports. */
// Reads a catalog or computed color as 0-255 channels and an alpha. Mixed tokens are
// color-mix() values that compute to color(srgb ...), while the catalog lists them rounded.
function colorKey(value: string | number) {
  const text = String(value);
  const alpha = (raw?: string) => Number(Number(raw ?? 1).toFixed(3));
  const hex = /^#([0-9A-F]{6})$/i.exec(text);
  if (hex) {
    const n = Number.parseInt(hex[1], 16);
    return `${n >> 16} ${(n >> 8) & 255} ${n & 255} / 1`;
  }
  const rgb =
    /^rgba?\((\d+)[, ]+(\d+)[, ]+(\d+)(?:\s*[,/]\s*([\d.]+))?\)$/.exec(text);
  if (rgb) return `${rgb[1]} ${rgb[2]} ${rgb[3]} / ${alpha(rgb[4])}`;
  const srgb =
    /^color\(srgb ([\d.e-]+) ([\d.e-]+) ([\d.e-]+)(?: \/ ([\d.]+))?\)$/.exec(
      text,
    );
  if (srgb) {
    const channels = [srgb[1], srgb[2], srgb[3]].map((channel) =>
      Math.round(Number(channel) * 255),
    );
    return `${channels.join(" ")} / ${alpha(srgb[4])}`;
  }
  throw new Error(`Unexpected color ${text}`);
}

const descriptions: Record<string, string | undefined> = tokens.descriptions;

const colorMap = (group: object) =>
  Object.fromEntries(
    leaves(group)
      .filter(([, value]) => typeof value === "string")
      .map(([name, value]) => [name, colorKey(value)]),
  );

const drawnColors = (drawn: Record<string, string>) =>
  Object.fromEntries(
    Object.entries(drawn).map(([name, value]) => [name, colorKey(value)]),
  );

test("Foundations draw every generated token in both themes", async ({
  page,
}) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto("/design-system#foundations");
  const foundations = page.locator("#foundations");

  // Each nested theme preview draws its own resolved colors.
  for (const theme of ["light", "dark"] as const) {
    const drawn = await foundations
      .locator(`#colors [data-theme="${theme}"] [data-color]`)
      .evaluateAll((swatches) =>
        Object.fromEntries(
          swatches.map((swatch) => [
            swatch.getAttribute("data-color"),
            getComputedStyle(swatch.querySelector("span")!).backgroundColor,
          ]),
        ),
      );
    expect(drawnColors(drawn)).toEqual(colorMap(tokens.color[theme]));
  }

  // Text roles resolve their whole typography through the role variables.
  const roles = await foundations
    .locator("[data-type-role]")
    .evaluateAll((rows) =>
      rows.map((row) => {
        const style = getComputedStyle(row.querySelector("p")!);
        return {
          name: row.getAttribute("data-type-role")!,
          fontSize: Number.parseFloat(style.fontSize),
          fontWeight: Number(style.fontWeight),
          letterSpacing: Number.parseFloat(style.letterSpacing) || 0,
          lineHeight: Number.parseFloat(style.lineHeight),
          textTransform: style.textTransform,
        };
      }),
    );
  expect(roles.map((role) => role.name)).toEqual(Object.keys(tokens.type));
  for (const drawn of roles) {
    const role = tokens.type[drawn.name as keyof typeof tokens.type];
    expect(drawn.fontSize, drawn.name).toBe(role.fontSize);
    expect(drawn.fontWeight, drawn.name).toBe(role.fontWeight);
    expect(drawn.letterSpacing, drawn.name).toBeCloseTo(role.letterSpacing, 2);
    expect(drawn.lineHeight, drawn.name).toBeCloseTo(
      role.fontSize * role.lineHeight,
      1,
    );
    expect(drawn.textTransform, drawn.name).toBe(
      role.textCase === "uppercase" ? "uppercase" : "none",
    );
  }

  // Every Web icon is drawn; single-platform icons are marked as such.
  const icons = Object.entries(tokens.icon);
  const webIcons = icons.filter(([, icon]) => icon.platforms.includes("web"));
  await expect(page.locator("#identity [data-icon] svg")).toHaveCount(
    webIcons.length,
  );
  await expect(
    page.locator("#identity [data-icon]").filter({ hasText: "Web only" }),
  ).toHaveText(
    webIcons
      .filter(([, icon]) => !icon.platforms.includes("ios"))
      .map(([name]) => new RegExp(`^${name}`)),
  );
  await expect(page.locator("#native-icons code")).toHaveText(
    icons
      .filter(([, icon]) => !icon.platforms.includes("web"))
      .map(([name]) => name),
  );

  // Layout reads page widths and layers from the tokens.
  for (const [name, width] of Object.entries(tokens.layout.pageWidth)) {
    await expect(
      page.locator(`#layout [data-page-width="${name}"]`),
    ).toContainText(`${width}px · ${descriptions[`layout.pageWidth.${name}`]}`);
  }
  await expect(page.locator("#layers code")).toHaveText(
    Object.keys(tokens.layout.layer),
  );
  // Every focus offset draws a ring at its own gap.
  const offsets = Object.entries(tokens.state.light.focus).filter(([name]) =>
    name.startsWith("ringOffset"),
  );
  expect(
    await page
      .locator("#state [data-focus-offset]")
      .evaluateAll((samples) =>
        samples.map((sample) => [
          sample.getAttribute("data-focus-offset"),
          getComputedStyle(sample).outlineOffset,
        ]),
      ),
  ).toEqual(offsets.map(([name, value]) => [name, `${value}px`]));
  await expect(page.locator("#breakpoints [data-breakpoint]")).toHaveCount(
    Object.keys(tokens.layout.breakpoint).length,
  );

  for (const theme of ["light", "dark"] as const) {
    for (const width of [1280, 390, 320]) {
      await test.step(`${theme} at ${width}px`, async () => {
        await page.setViewportSize({ width, height: 900 });
        await expect(async () => {
          await page.getByLabel("Gallery theme").selectOption(theme);
          await expect(
            page.locator("[data-theme]").filter({ has: foundations }),
          ).toHaveAttribute("data-theme", theme);
        }).toPass();
        const states = await page
          .locator("#state [data-state]")
          .evaluateAll((swatches) =>
            Object.fromEntries(
              swatches.map((swatch) => [
                swatch.getAttribute("data-state"),
                getComputedStyle(swatch.querySelector("span")!).backgroundColor,
              ]),
            ),
          );
        expect(drawnColors(states)).toEqual(colorMap(tokens.state[theme]));
        expect(
          colorKey(
            await page
              .locator('#elevation [data-elevation="overlay"]')
              .evaluate((element) => getComputedStyle(element).backgroundColor),
          ),
        ).toBe(colorKey(tokens.elevation[theme].overlay.scrim));
        for (const material of await page
          .locator("#material [data-material]")
          .all()) {
          await expect(material).not.toHaveCSS("backdrop-filter", "none");
        }
        expect(
          await page.evaluate(
            () => document.documentElement.scrollWidth <= window.innerWidth,
          ),
        ).toBe(true);
        await foundations.screenshot({
          animations: "disabled",
          caret: "initial",
          path: `/private/tmp/memotrail-foundations-${theme}-${width}.png`,
        });
        await page.locator("#layout").screenshot({
          animations: "disabled",
          path: `/private/tmp/memotrail-layout-tokens-${theme}-${width}.png`,
        });
      });
    }
  }
  expect(errors).toEqual([]);
});

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

test("the gallery shows every specimen the component specs list", async ({
  page,
}) => {
  const kebab = (value: string) =>
    value.replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase();
  await page.goto("/design-system");

  // Each listed specimen appears exactly once, and nothing claims an id no spec lists.
  const shown = await page
    .locator("[data-specimen]")
    .evaluateAll((elements) =>
      elements.map((element) => element.getAttribute("data-specimen")),
    );
  expect(shown.toSorted()).toEqual(
    componentSpecimens.map(({ id }) => id).toSorted(),
  );

  for (const specimen of componentSpecimens) {
    const section = page.locator(`[data-specimen="${specimen.id}"]`);
    await section.scrollIntoViewIfNeeded();
    await expect(section).toBeVisible();
    await expect(
      section.getByRole("heading", { name: specimen.id, exact: true }),
    ).toBeVisible();
    await expect(section).toContainText(specimen.description);

    // It draws the spec's component, in every value the spec says it covers.
    const component = `[data-ui-${kebab(specimen.component)}]`;
    await expect(section.locator(component).first()).toBeVisible();
    for (const [prop, values] of Object.entries(specimen.covers)) {
      for (const value of values as readonly string[]) {
        await expect(
          section
            .locator(`${component}[data-${kebab(prop)}="${value}"]`)
            .first(),
          `${specimen.id} draws ${prop} ${value}`,
        ).toBeVisible();
      }
    }
  }
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
    .locator('[data-specimen="button-variants"]')
    .getByRole("button", { name: "Danger", exact: true })
    .click();
  await expect(review.getByRole("status")).toHaveText(
    "danger button activated.",
  );
  for (const button of await review
    .locator('[data-specimen="button-disabled"] button')
    .all()) {
    await expect(button).toBeDisabled();
  }
  for (const button of await review
    .locator('[data-specimen="button-loading"] button')
    .all()) {
    await expect(button).toBeDisabled();
    await expect(button).toHaveAttribute("aria-busy", "true");
  }
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

test("Checkbox is a native input with a name, a description, a focus ring, and form values", async ({
  page,
}) => {
  await page.goto("/design-system#checkbox");
  const specimen = page.locator("#checkbox");
  await specimen.scrollIntoViewIfNeeded();
  const named = (name: string) =>
    specimen.getByRole("checkbox", { name, exact: true });

  // The label names the input and the description is announced after it.
  const remind = named("Remind me");
  await expect(remind).not.toBeChecked();
  await expect(remind).toHaveAccessibleDescription("Controlled by this page");
  await expect(remind).toHaveJSProperty("type", "checkbox");
  await expect(named("Unchecked")).toHaveAccessibleDescription("");
  await expect(named("Checked")).toBeChecked();

  // A click on the label text toggles it, and the controlled state follows.
  await specimen.getByText("Remind me", { exact: true }).click();
  await expect(remind).toBeChecked();
  await expect(specimen.getByRole("status")).toContainText("Remind me is on.");
  await remind.focus();
  await page.keyboard.press("Space");
  await expect(remind).not.toBeChecked();

  // Disabled controls cannot change and read as unavailable.
  for (const name of ["Disabled", "Disabled checked"]) {
    const disabled = named(name);
    await expect(disabled).toBeDisabled();
    await disabled.click({ force: true });
  }
  await expect(named("Disabled")).not.toBeChecked();
  await expect(named("Disabled checked")).toBeChecked();

  // The drawn box tracks the input, in both sizes.
  const box = (name: string) =>
    named(name).locator("xpath=following-sibling::span[1]");
  await expect(box("Unchecked")).toHaveCSS("width", "20px");
  await expect(box("Small unchecked")).toHaveCSS("width", "16px");
  await expect(box("Checked")).toHaveCSS("background-color", "rgb(49, 94, 79)");
  await expect(box("Unchecked")).toHaveCSS(
    "background-color",
    "rgb(251, 249, 243)",
  );

  // Keyboard focus draws a ring around the box.
  await named("Unchecked").focus();
  await page.keyboard.press("Shift+Tab");
  await page.keyboard.press("Tab");
  await expect(named("Unchecked")).toBeFocused();
  await expect(box("Unchecked")).toHaveCSS("outline-style", "solid");
  await expect(box("Unchecked")).toHaveCSS("outline-width", "2px");

  // Inside a form, a checked box submits its name and value and an unchecked one does not.
  const form = specimen.locator("form");
  await form.getByRole("button", { name: "Submit form" }).click();
  await expect(specimen.getByRole("status")).toContainText(
    'Submitted: {"photos":"yes"}',
  );
  await form.getByRole("checkbox", { name: "Include photos" }).uncheck();
  await form.getByRole("checkbox", { name: "Include Trash" }).check();
  await form.getByRole("button", { name: "Submit form" }).click();
  await expect(specimen.getByRole("status")).toContainText(
    'Submitted: {"trash":"yes"}',
  );

  for (const [theme, width] of [
    ["light", 1280],
    ["dark", 390],
  ] as const) {
    await page.setViewportSize({ width, height: 900 });
    await page.emulateMedia({ colorScheme: theme });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await specimen.screenshot({
      caret: "initial",
      path: `/private/tmp/memotrail-checkbox-${theme}-${width}.png`,
    });
  }
});

test("SectionHeader renders section and list headings at the level the caller picks", async ({
  page,
}) => {
  await page.goto("/design-system#section-header");
  const specimen = page.locator("#section-header");
  await specimen.scrollIntoViewIfNeeded();
  const header = (name: string) =>
    specimen.locator(`[data-header="${name}"] [data-ui-section-header]`);

  // The gallery sits below an h3 specimen title, so its headers are h4.
  await expect(
    specimen.getByRole("heading", { level: 4, name: "Recent Entries" }),
  ).toBeVisible();
  await expect(specimen.getByRole("heading", { level: 2 })).toHaveCount(0);

  // Section is a serif title; list is a small uppercase heading.
  const sectionTitle = specimen.getByRole("heading", {
    name: "Recent Entries",
  });
  await expect(sectionTitle).toHaveCSS("text-transform", "none");
  await expect(sectionTitle).toHaveCSS("font-size", "20px");
  const listTitle = header("list").getByRole("heading");
  await expect(listTitle).toHaveCSS("text-transform", "uppercase");
  await expect(listTitle).toHaveCSS("font-size", "13px");
  await expect(listTitle).toHaveCSS("font-weight", "600");
  const family = (title: typeof sectionTitle) =>
    title.evaluate((element) => getComputedStyle(element).fontFamily);
  expect(await family(sectionTitle)).not.toBe(await family(listTitle));

  // Detail sits beside the title by default and at the trailing edge on request.
  const start = header("list");
  const startTitle = await start.getByRole("heading").boundingBox();
  const startDetail = await start.getByText("12 items").boundingBox();
  expect(startDetail!.x).toBeGreaterThan(startTitle!.x + startTitle!.width);
  expect(startDetail!.x).toBeLessThan(startTitle!.x + startTitle!.width + 24);
  const end = header("list-end");
  const endDetail = await end.getByText("12 items").boundingBox();
  const endAction = await end
    .getByRole("link", { name: "3 need organizing" })
    .boundingBox();
  const endBox = await end.boundingBox();
  expect(endAction!.x + endAction!.width).toBeCloseTo(
    endBox!.x + endBox!.width,
    0,
  );
  expect(endDetail!.x + endDetail!.width).toBeLessThan(endAction!.x);
  expect(endDetail!.x).toBeGreaterThan(
    (await end.getByRole("heading").boundingBox())!.x + 200,
  );

  // A description reads under the title and the action centers on the block.
  const described = header("section-description");
  const describedTitle = await described.getByRole("heading").boundingBox();
  const describedText = await described
    .getByText("Pinned to the top of your Library.")
    .boundingBox();
  expect(describedText!.y).toBeGreaterThan(
    describedTitle!.y + describedTitle!.height - 1,
  );
  const edit = await described
    .getByRole("button", { name: "Edit" })
    .boundingBox();
  const block = await described.boundingBox();
  expect(edit!.y + edit!.height / 2).toBeCloseTo(
    block!.y + block!.height / 2,
    0,
  );
  await expect(header("list-description").getByText("Connected")).toBeVisible();

  // A long heading wraps instead of overflowing, and the action stays reachable.
  for (const width of [1280, 390, 320]) {
    await page.setViewportSize({ width, height: 900 });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    const long = header("long");
    await expect(long.getByRole("link", { name: "View all" })).toBeVisible();
    const longBox = await long.boundingBox();
    const longTitle = await long.getByRole("heading").boundingBox();
    expect(longTitle!.x + longTitle!.width).toBeLessThanOrEqual(
      longBox!.x + longBox!.width + 0.5,
    );
  }

  for (const [theme, width] of [
    ["light", 1280],
    ["dark", 390],
  ] as const) {
    await page.setViewportSize({ width, height: 900 });
    await page.emulateMedia({ colorScheme: theme });
    await specimen.screenshot({
      caret: "initial",
      path: `/private/tmp/memotrail-section-header-${theme}-${width}.png`,
    });
  }
});

test("Skeleton is decorative, shimmers, and stands still for reduced motion", async ({
  page,
}) => {
  await page.goto("/design-system#skeleton");
  const specimen = page.locator("#skeleton");
  await specimen.scrollIntoViewIfNeeded();
  const skeletons = specimen.locator("[data-ui-skeleton]");
  const shape = (name: string) =>
    specimen.locator(`[data-skeleton="${name}"] [data-ui-skeleton]`).first();

  // Placeholders add nothing to the accessibility tree.
  await expect(skeletons).toHaveCount(10);
  for (const skeleton of await skeletons.all())
    await expect(skeleton).toHaveAttribute("aria-hidden", "true");
  await expect(specimen.getByRole("img")).toHaveCount(0);
  await expect(specimen.getByRole("progressbar")).toHaveCount(0);

  // Shapes: a circle is square and round, a line is thin, fill takes its frame.
  const circle = await shape("circle").boundingBox();
  expect(circle!.width).toBeCloseTo(48, 0);
  expect(circle!.height).toBeCloseTo(48, 0);
  await expect(shape("circle")).toHaveCSS("border-radius", "50%");
  expect((await shape("line").boundingBox())!.height).toBeCloseTo(14, 0);
  const frame = await specimen
    .locator('[data-skeleton="fill"] > div')
    .boundingBox();
  const fill = await shape("fill").boundingBox();
  expect(fill!.width).toBeCloseTo(frame!.width, 0);
  expect(fill!.height).toBeCloseTo(frame!.height, 0);
  expect((await shape("block").boundingBox())!.height).toBeCloseTo(64, 0);

  // The shimmer runs by default, stops on request, and stops for reduced motion.
  await expect(shape("block")).toHaveCSS("animation-name", /shimmer/);
  await expect(shape("still")).toHaveCSS("animation-name", "none");
  await page.emulateMedia({ reducedMotion: "reduce" });
  await expect(shape("block")).toHaveCSS("animation-name", "none");
  await expect(shape("fill")).toHaveCSS("animation-name", "none");

  for (const [theme, width] of [
    ["light", 1280],
    ["dark", 390],
  ] as const) {
    await page.setViewportSize({ width, height: 900 });
    await page.emulateMedia({ colorScheme: theme });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await specimen.screenshot({
      animations: "disabled",
      caret: "initial",
      path: `/private/tmp/memotrail-skeleton-${theme}-${width}.png`,
    });
  }
});
