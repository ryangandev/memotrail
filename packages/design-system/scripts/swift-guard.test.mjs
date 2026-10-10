import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { before, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { resolveSystem } from "./lib/resolve.mjs";
import {
  allowances,
  checkSwiftSources,
  codeOnly,
  formatFailure,
  scanSwift,
  suggest,
  swiftSourceRoot,
  tokenFiles,
  tokenIndex,
} from "./lib/swift-guard.mjs";

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repositoryRoot = resolve(packageRoot, "../..");
const tokenDirectory = resolve(packageRoot, "tokens");

let system;
let index;
before(async () => {
  system = await resolveSystem({
    resolverPath: resolve(tokenDirectory, "soft-ledger.resolver.json"),
    tokenDirectory,
    root: repositoryRoot,
  });
  index = tokenIndex(system);
});

/** The findings for one snippet as `rule value` strings, in source order. */
const scan = (source) =>
  scanSwift(source).map((finding) =>
    finding.value === undefined
      ? finding.rule
      : `${finding.rule} ${finding.value}`,
  );

/** The suggestions for the first finding in a snippet. */
const suggestFor = (source) => {
  const [finding] = scanSwift(source);
  assert.ok(finding, `expected a finding in ${source}`);
  return suggest(finding, index);
};

describe("scanSwift", () => {
  test("flags literal fonts, the retired MTTypography, and literal tracking", () => {
    assert.deepEqual(
      scan(`Text("A").font(.system(size: 15, weight: .medium))`),
      ["font"],
    );
    assert.deepEqual(scan(`Text("A").font(.subheadline)`), ["font"]);
    assert.deepEqual(scan(`Text("A").font(Font.caption.weight(.semibold))`), [
      "font",
      "font",
    ]);
    assert.deepEqual(
      scan(`Text("A").font(isRegular ? MTFont.body : .footnote)`),
      ["font"],
    );
    assert.deepEqual(scan(`Text("A").font(MTTypography.caption)`), [
      "legacy-typography",
    ]);
    assert.deepEqual(scan(`let font = UIFont.systemFont(ofSize: 17)`), [
      "font",
    ]);
    assert.deepEqual(scan(`Text("A").tracking(0.8)`), ["tracking 0.8"]);
    assert.deepEqual(scan(`Text("A").font(MTFont.caption).tracking(0)`), []);
  });

  test("flags icon sizes written as numbers, not icon size tokens", () => {
    assert.deepEqual(
      scan(`Image(systemName: "x").font(.mtIcon(17, weight: .medium))`),
      ["font 17"],
    );
    assert.deepEqual(
      scan(`Image(systemName: "x").font(.mtIcon(MTSize.Icon.s17))`),
      [],
    );
  });

  test("flags literal colors, system colors, and literal opacity", () => {
    assert.deepEqual(
      scan(`Color(red: 24 / 255, green: 24 / 255, blue: 20 / 255)`),
      ["color"],
    );
    assert.deepEqual(scan(`Text("A").foregroundStyle(.white)`), [
      "system-color",
    ]);
    assert.deepEqual(scan(`view.background(Color.black)`), ["system-color"]);
    assert.deepEqual(scan(`view.background(UIColor.secondaryLabel)`), [
      "system-color",
    ]);
    assert.deepEqual(
      scan(`view.foregroundStyle(MTColor.accent.opacity(0.34))`),
      ["opacity 0.34"],
    );
    assert.deepEqual(scan(`view.opacity(isVisible ? 1 : 0)`), []);
  });

  test("flags materials, shadows, and animation timing", () => {
    assert.deepEqual(scan(`view.background(.ultraThinMaterial)`), ["material"]);
    assert.deepEqual(scan(`view.shadow(color: MTColor.ink, radius: 4)`), [
      "shadow",
    ]);
    assert.deepEqual(scan(`withAnimation(.easeOut(duration: 0.2)) {}`), [
      "animation",
      "animation 0.2",
    ]);
    assert.deepEqual(
      scan(`withAnimation(.snappy(duration: MTMotion.quick)) {}`),
      ["animation"],
    );
    assert.deepEqual(
      scan(
        `withAnimation(MTEasing.enter.animation(duration: MTMotion.quick).delay(0.1)) {}`,
      ),
      ["animation 0.1"],
    );
    assert.deepEqual(
      scan(
        `withAnimation(MTEasing.enter.animation(duration: MTMotion.quick)) {}`,
      ),
      [],
    );
  });

  test("flags layout literals in padding, frames, offsets, labeled arguments, and constants", () => {
    assert.deepEqual(scan(`view.padding(12)`), ["layout 12"]);
    assert.deepEqual(scan(`view.padding(.horizontal, 8).padding(.top, 0)`), [
      "layout 8",
    ]);
    assert.deepEqual(scan(`view.frame(width: 44, height: MTSize.hitTarget)`), [
      "layout 44",
    ]);
    assert.deepEqual(scan(`view.offset(x: 3, y: -3)`), [
      "layout 3",
      "layout 3",
    ]);
    assert.deepEqual(scan(`VStack(alignment: .leading, spacing: 6) {}`), [
      "layout 6",
    ]);
    assert.deepEqual(scan(`RoundedRectangle(cornerRadius: 10)`), ["layout 10"]);
    assert.deepEqual(scan(`shape.stroke(MTColor.border, lineWidth: 2)`), [
      "layout 2",
    ]);
    assert.deepEqual(
      scan(`StrokeStyle(lineWidth: MTSize.Stroke.thin, dash: [4, 3])`),
      ["layout 4", "layout 3"],
    );
    assert.deepEqual(scan(`GridItem(.adaptive(minimum: 220))`), ["layout 220"]);
    assert.deepEqual(scan(`private let stripe: CGFloat = 12`), ["layout 12"]);
    assert.deepEqual(
      scan(`@ScaledMetric(relativeTo: .body) private var gap = 11`),
      ["layout 11"],
    );
    assert.deepEqual(scan(`view.scaleEffect(isPressed ? 0.99 : 1)`), [
      "layout 0.99",
    ]);
  });

  test("flags sizes passed to components and kept in properties", () => {
    assert.deepEqual(
      scan(`MTRecordCardVisual(height: isRegular ? 138 : 125) {}`),
      ["layout 138", "layout 125"],
    );
    assert.deepEqual(
      scan(`MTRichTextEditor(text: $text, minimumHeight: 120)`),
      ["layout 120"],
    );
    assert.deepEqual(scan(`  var minimumHeight = 180.0`), ["layout 180"]);
    assert.deepEqual(
      scan(`let columnWidth = (width - spacing * CGFloat(columns - 1)) / 2`),
      [],
    );
    assert.deepEqual(scan(`static let pageSize = 100`), []);
    assert.deepEqual(
      scan(
        `var height: CGFloat {\n  switch self {\n  case .small: 34\n  case .large: MTSize.Control.large\n  }\n}`,
      ),
      ["layout 34"],
    );
    assert.deepEqual(
      scan(`var sortRank: Int {\n  switch self {\n  case .a: 10\n  }\n}`),
      [],
    );
  });

  test("flags gradient stops, unit points, and radii but not the edges", () => {
    assert.deepEqual(
      scan(
        `LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: MTColor.ink, location: 1)], startPoint: UnitPoint(x: 0, y: 0.4), endPoint: .trailing)`,
      ),
      ["gradient 0.35", "gradient 0.4"],
    );
    assert.deepEqual(
      scan(
        `RadialGradient(colors: [], center: .center, startRadius: 0, endRadius: 140)`,
      ),
      ["gradient 140"],
    );
  });

  test("treats a number multiplying or dividing a token as arithmetic", () => {
    assert.deepEqual(
      scan(`view.frame(minHeight: height - 2 * MTSpacing.s5)`),
      [],
    );
    assert.deepEqual(scan(`view.frame(width: MTSize.hitTarget / 2)`), []);
    assert.deepEqual(scan(`view.frame(width: MTSize.hitTarget * 0.5)`), []);
    assert.deepEqual(scan(`view.frame(width: MTSize.hitTarget + 4)`), [
      "layout 4",
    ]);
  });

  test("ignores comments and string contents but not interpolated code", () => {
    assert.deepEqual(
      scan(
        `// .padding(12)\n/* .font(.body) */\nText(".padding(12) and .white")`,
      ),
      [],
    );
    assert.deepEqual(scan(`Text("\\(value)").padding(12)`), ["layout 12"]);
    assert.deepEqual(scan('Text("\\(Text("A").padding(5))")'), ["layout 5"]);
    assert.equal(codeOnly(`a // b\nc`), "a     \nc");
  });

  test("reports 1-based lines and the trimmed source line", () => {
    const [finding] = scanSwift(
      `struct A {\n  var body: some View {\n    Text("A").padding(12)\n  }\n}`,
    );
    assert.equal(finding.line, 3);
    assert.equal(finding.text, `Text("A").padding(12)`);
  });
});

describe("suggest", () => {
  test("names the spacing, layout, and size tokens with the same value", () => {
    assert.ok(suggestFor(`view.padding(16)`).includes("MTSpacing.s4"));
    assert.ok(
      suggestFor(`view.frame(width: 44, height: 44)`).includes(
        "MTSize.hitTarget",
      ),
    );
    assert.ok(
      suggestFor(`view.frame(height: 190)`).includes(
        "MTLayout.RecordCard.visualHeight",
      ),
    );
  });

  test("keeps icon and stroke sizes out of gaps and frames", () => {
    const gap = suggestFor(`VStack(spacing: 2) {}`);
    assert.ok(!gap.some((reference) => reference.startsWith("MTSize.Stroke.")));
    assert.ok(gap.includes("MTSpacing.lineGap"));
    const frame = suggestFor(`view.frame(width: 17)`);
    assert.ok(!frame.some((reference) => reference.startsWith("MTSize.Icon.")));
    assert.ok(
      suggestFor(`shape.stroke(MTColor.border, lineWidth: 1)`).includes(
        "MTSize.Stroke.thin",
      ),
    );
    assert.deepEqual(suggestFor(`Image(systemName: "x").font(.mtIcon(17))`), [
      "MTSize.Icon.s17",
    ]);
  });

  test("names fonts, tracked roles, translucent colors, durations, and curves", () => {
    assert.ok(
      suggestFor(`Text("A").font(.subheadline)`).includes("MTFont.body"),
    );
    assert.ok(
      suggestFor(
        `Text("A").font(.system(.title, design: .serif).weight(.medium))`,
      ).includes("MTFont.title"),
    );
    assert.ok(
      suggestFor(`Text("A").tracking(0.8)`).includes(
        "mtTextRole(.cardEyebrow)",
      ),
    );
    assert.deepEqual(
      suggestFor(`view.background(MTColor.accent.opacity(0.34))`),
      ["MTColor.accentBorder"],
    );
    assert.ok(
      suggestFor(
        `view.background(Color(red: 24 / 255, green: 24 / 255, blue: 20 / 255).opacity(0.72))`,
      ).includes("MTColor.inverseSurface"),
    );
    assert.deepEqual(
      suggestFor(`withAnimation(MTEasing.enter.animation(duration: 0.18)) {}`),
      ["MTMotion.standard"],
    );
    assert.deepEqual(suggestFor(`withAnimation(.easeInOut) {}`), [
      "MTEasing.inOut.animation(duration:)",
    ]);
    assert.deepEqual(
      suggestFor(`view.background(.ultraThinMaterial)`),
      ["MTMaterial.glassPanel", "MTMaterial.chip"].filter((reference) =>
        index.materials.some((m) => m.reference === reference),
      ),
    );
  });

  test("says when no token has the value", () => {
    const [finding] = scanSwift(`view.padding(123.5)`);
    const failure = {
      ...finding,
      file: `${swiftSourceRoot}/A.swift`,
      message: "Literal layout value",
      suggestions: suggest(finding, index),
    };
    assert.deepEqual(failure.suggestions, []);
    assert.equal(
      formatFailure(failure),
      `${swiftSourceRoot}/A.swift:1:14: Literal layout value 123.5. No token has this value yet; add one to packages/design-system/tokens.\n    view.padding(123.5)`,
    );
  });
});

describe("tokenIndex", () => {
  test("names only symbols that DesignTokens.swift declares", async () => {
    const swift = await readFile(
      join(
        repositoryRoot,
        swiftSourceRoot,
        "DesignSystem/Generated/DesignTokens.swift",
      ),
      "utf8",
    );
    const declared = new Set();
    const scopes = [];
    for (const line of swift.split("\n")) {
      const indent = line.length - line.trimStart().length;
      const scope = /^\s*(?:enum|struct|extension)\s+(\w+)[^{]*\{\s*$/.exec(
        line,
      );
      if (scope) {
        scopes.push({ name: scope[1], indent });
        continue;
      }
      if (/^\s*\}\s*$/.test(line) && scopes.at(-1)?.indent === indent) {
        scopes.pop();
        continue;
      }
      const member = /^\s*(?:static\s+(?:let|var)|case)\s+(\w+)/.exec(line);
      if (member) {
        declared.add(
          [...scopes.map((entry) => entry.name), member[1]].join("."),
        );
      }
    }

    const references = [
      ...index.dimensions,
      ...index.numbers,
      ...index.durations,
      ...index.colors,
      ...index.shadows,
      ...index.materials,
    ].map((token) => token.reference);
    for (const role of index.roles) {
      references.push(role.font ? role.reference : `MTTextRole.${role.name}`);
    }
    assert.ok(references.length > 300);
    for (const reference of references) {
      const symbol = reference.replace(/\.rawValue$/, "");
      assert.ok(
        declared.has(symbol),
        `${reference} is not declared in DesignTokens.swift`,
      );
    }
  });
});

describe("checkSwiftSources", () => {
  /** Writes Swift files under a temporary repository root and checks them. */
  async function check(files, allowed) {
    const root = await mkdtemp(join(tmpdir(), "memotrail-swift-guard-"));
    try {
      for (const [path, source] of Object.entries(files)) {
        const full = join(root, swiftSourceRoot, path);
        await mkdir(dirname(full), { recursive: true });
        await writeFile(full, source);
      }
      return await checkSwiftSources({ root, system, allowed });
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  }

  test("skips the token files and reports each finding with its file and suggestions", async () => {
    const { failures, stale } = await check(
      {
        "DesignSystem/Generated/DesignTokens.swift":
          "let a = Font.system(size: 15)\n",
        "DesignSystem/Components/MTFoundations.swift":
          "let b = Font.system(size: 15)\n",
        "Features/A.swift": 'Text("A")\n  .padding(16)\n',
      },
      [],
    );
    assert.deepEqual(stale, []);
    assert.equal(failures.length, 1);
    assert.equal(failures[0].file, `${swiftSourceRoot}/Features/A.swift`);
    assert.equal(failures[0].line, 2);
    assert.ok(failures[0].suggestions.includes("MTSpacing.s4"));
  });

  test("excuses findings an allowance names and reports allowances that match nothing", async () => {
    const allowed = [
      {
        file: "Features/A.swift",
        rule: "system-color",
        match: "Color.black",
        reason: "Mask.",
      },
      { file: "Features/A.swift", rule: "layout", reason: "Diagram." },
      {
        file: "Features/A.swift",
        rule: "font",
        match: ".bold()",
        reason: "Unused.",
      },
    ];
    const { failures, stale } = await check(
      {
        "Features/A.swift":
          "view.background(Color.black).padding(3)\nview.foregroundStyle(.white)\n",
      },
      allowed,
    );
    assert.deepEqual(
      failures.map((failure) => `${failure.rule}:${failure.line}`),
      ["system-color:2"],
    );
    assert.deepEqual(stale, [allowed[2]]);
  });

  test("passes the app sources with every allowance in use", async () => {
    const { failures, stale } = await checkSwiftSources({
      root: repositoryRoot,
      system,
    });
    assert.deepEqual(failures.map(formatFailure), []);
    assert.deepEqual(stale, []);
  });

  test("gives every token file and allowance a reason", () => {
    for (const reason of tokenFiles.values()) assert.ok(reason.length > 20);
    for (const allowance of allowances) {
      assert.ok(allowance.file && allowance.rule, JSON.stringify(allowance));
      assert.ok(
        allowance.reason.length > 20,
        `${allowance.file} needs a reason`,
      );
    }
  });
});
