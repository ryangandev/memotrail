import { existsSync, mkdirSync, readdirSync, readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "@playwright/test";
import { bundled } from "./catalog.mjs";
import { compileTokens } from "./compile-tokens.mjs";
import { loadSpecs } from "./docs.mjs";
import { kebabCase } from "../lib/util.mjs";
import { cardMarker } from "./validate.mjs";

// Loads each exported preview card the way the Claude Design copy frames it: the compiled tokens
// CSS, bundle.css, React 18 UMD, and bundle.js, with data-theme on the root element. Every card
// must render in both themes without console errors, fit its declared height, and fit the card
// width. A card made from a spec shows each of its specimens in every value the specimen covers.
// Screenshots land in dist/claude-design/screenshots.

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const output = resolve(
  process.env.CLAUDE_DESIGN_OUTPUT ?? join(packageRoot, "dist/claude-design"),
);
const project = join(output, "project");
const screenshots = join(output, "screenshots");
const origin = "http://claude-design.test";
const cardWidth = 640;
// Card heights in catalog.mjs leave a little room for font differences, but not a blank band.
const maximumSlack = 80;
const require = createRequire(import.meta.url);
// The specs the export was made from; CLAUDE_DESIGN_SPECS matches an export made with --specs.
const rendered = new Set(bundled.map((component) => component.name));
const specs = new Map(
  (
    await loadSpecs(
      resolve(
        process.env.CLAUDE_DESIGN_SPECS ?? join(packageRoot, "components"),
      ),
      packageRoot,
    )
  ).map((spec) => [spec.name, spec]),
);

if (!existsSync(join(project, "tokens.json"))) {
  throw new Error(
    `No export in ${project}. Run pnpm design-system:export first.`,
  );
}
mkdirSync(screenshots, { recursive: true });

// The development builds report React warnings as console errors, which fail the check. React's
// exports map hides the UMD folder, so it is found from the package root.
function umd(name, file) {
  const manifest = require.resolve(`${name}/package.json`);
  const { version } = JSON.parse(readFileSync(manifest, "utf8"));
  if (!version.startsWith("18.")) {
    throw new Error(
      `The preview check needs ${name} 18 UMD, found ${version}.`,
    );
  }
  return readFileSync(join(dirname(manifest), "umd", file));
}

const files = {
  "/tokens.css": [
    compileTokens(
      JSON.parse(readFileSync(join(project, "tokens.json"), "utf8")),
    ),
    "text/css",
  ],
  "/vendor/react.js": [umd("react", "react.development.js"), "text/javascript"],
  "/vendor/react-dom.js": [
    umd("react-dom", "react-dom.development.js"),
    "text/javascript",
  ],
  "/components/bundle.css": [
    readFileSync(join(project, "components/bundle.css")),
    "text/css",
  ],
  "/components/bundle.js": [
    readFileSync(join(project, "components/bundle.js")),
    "text/javascript",
  ],
};

const cards = readdirSync(join(project, "components"), { withFileTypes: true })
  .filter((entry) => entry.isDirectory() && entry.name !== "Cover")
  .map((entry) => {
    const preview = readFileSync(
      join(project, "components", entry.name, "preview.html"),
      "utf8",
    );
    const marker = preview.split("\n", 1)[0].match(cardMarker);
    if (!marker)
      throw new Error(`${entry.name}/preview.html has no @dsCard marker.`);
    return { name: entry.name, preview, height: Number(marker[2]) };
  });

function frame(preview, theme) {
  return `<!doctype html>
<html data-theme="${theme}" lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="/tokens.css">
<link rel="stylesheet" href="/components/bundle.css">
<script src="/vendor/react.js"></script>
<script src="/vendor/react-dom.js"></script>
<script src="/components/bundle.js"></script>
</head>
<body>
${preview}
</body>
</html>`;
}

for (const card of cards) {
  for (const theme of ["light", "dark"]) {
    test(`${card.name} renders in ${theme}`, async ({ page }) => {
      const problems = [];
      page.on("console", (message) => {
        if (["error", "warning"].includes(message.type())) {
          problems.push(`console ${message.type()}: ${message.text()}`);
        }
      });
      page.on("pageerror", (error) =>
        problems.push(`page error: ${error.message}`),
      );
      await page.route("**/*", (route) => {
        const url = new URL(route.request().url());
        if (url.protocol === "data:") return route.continue();
        if (url.origin !== origin) {
          problems.push(`network request to ${url.href}`);
          return route.abort();
        }
        if (url.pathname === "/") {
          return route.fulfill({
            body: frame(card.preview, theme),
            contentType: "text/html; charset=utf-8",
          });
        }
        const file = files[url.pathname];
        if (!file) {
          problems.push(`request for a missing file ${url.pathname}`);
          return route.fulfill({ status: 404, body: "" });
        }
        return route.fulfill({ body: file[0], contentType: file[1] });
      });

      await page.setViewportSize({ width: cardWidth, height: card.height });
      await page.goto(`${origin}/`);
      await expect(page.locator("#root > *")).not.toHaveCount(0);
      await page.waitForLoadState("networkidle");
      await page.evaluate(() => document.fonts.ready);

      const size = await page.evaluate(() => {
        const root = document.getElementById("root");
        const box = root.getBoundingClientRect();
        return {
          text: root.innerText.trim().length,
          elements: root.querySelectorAll("*").length,
          bottom: Math.ceil(box.bottom + window.scrollY),
          width: document.documentElement.scrollWidth,
        };
      });
      await page.screenshot({
        path: join(screenshots, `${card.name}-${theme}.png`),
        animations: "disabled",
      });

      // A spec-only card describes the spec instead of rendering the component.
      const spec = specs.get(card.name);
      if (spec && rendered.has(card.name)) {
        const component = `[data-ui-${kebabCase(spec.name)}]`;
        for (const specimen of spec.specimens) {
          const section = page.locator(`[data-specimen="${specimen.id}"]`);
          await expect(section, `${specimen.id} is on the card`).toHaveCount(1);
          await expect(section).toContainText(specimen.description.trim());
          for (const [prop, values] of Object.entries(specimen.covers)) {
            for (const value of values) {
              await expect(
                section
                  .locator(`${component}[data-${kebabCase(prop)}="${value}"]`)
                  .first(),
                `${specimen.id} draws ${prop} ${value}`,
              ).toBeVisible();
            }
          }
        }
      }

      expect(size.elements, "the card renders elements").toBeGreaterThan(1);
      expect(problems, "console and network problems").toEqual([]);
      expect(
        size.bottom,
        `content fits the ${card.height}px card`,
      ).toBeLessThanOrEqual(card.height);
      expect(
        card.height - size.bottom,
        `the ${card.height}px card leaves at most ${maximumSlack}px empty`,
      ).toBeLessThanOrEqual(maximumSlack);
      expect(
        size.width,
        `content fits the ${cardWidth}px card`,
      ).toBeLessThanOrEqual(cardWidth);
      test.info().annotations.push({
        type: "height",
        description: `${size.bottom}px of ${card.height}px`,
      });
    });
  }
}
