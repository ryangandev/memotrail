import { expect, type Locator } from "@playwright/test";

/**
 * Reads a row as it is drawn: every visible word and "·" separator, grouped
 * into the lines the row wraps onto. Anything clipped out of view is left out,
 * and words that are only partly visible are reported separately.
 */
export async function readRenderedLines(row: Locator) {
  return row.evaluate((root) => {
    type Box = { left: number; right: number; top: number; bottom: number };
    const tokens: { text: string; left: number; middle: number }[] = [];
    const clippedWords: string[] = [];

    // Overflow clips to the padding box, on each axis that does not stay visible.
    function clipBox(element: Element): Box {
      const style = getComputedStyle(element);
      const rect = element.getBoundingClientRect();
      const left = rect.left + element.clientLeft;
      const top = rect.top + element.clientTop;
      const clipsX = style.overflowX !== "visible";
      const clipsY = style.overflowY !== "visible";
      return {
        left: clipsX ? left : -Infinity,
        right: clipsX ? left + element.clientWidth : Infinity,
        top: clipsY ? top : -Infinity,
        bottom: clipsY ? top + element.clientHeight : Infinity,
      };
    }

    function visibleBox(rect: DOMRect, from: Element): Box {
      const box = {
        left: rect.left,
        right: rect.right,
        top: rect.top,
        bottom: rect.bottom,
      };
      for (let element: Element | null = from; element;) {
        const clip = clipBox(element);
        box.left = Math.max(box.left, clip.left);
        box.right = Math.min(box.right, clip.right);
        box.top = Math.max(box.top, clip.top);
        box.bottom = Math.min(box.bottom, clip.bottom);
        element = element.parentElement;
      }
      return box;
    }

    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const parent = node.parentElement;
      if (
        !parent ||
        !parent.checkVisibility({
          opacityProperty: true,
          visibilityProperty: true,
        })
      )
        continue;
      for (const match of (node.textContent ?? "").matchAll(/\S+/g)) {
        const range = document.createRange();
        range.setStart(node, match.index);
        range.setEnd(node, match.index + match[0].length);
        for (const rect of range.getClientRects()) {
          if (rect.width === 0) continue;
          const visible = visibleBox(rect, parent);
          const width = visible.right - visible.left;
          const height = visible.bottom - visible.top;
          if (width < 0.5 || height < 0.5) continue;
          if (match[0] !== "·" && width < rect.width - 0.5)
            clippedWords.push(match[0]);
          tokens.push({
            text: match[0],
            left: rect.left,
            middle: (rect.top + rect.bottom) / 2,
          });
        }
      }
    }

    // Items on one line share a vertical middle, whatever their heights.
    const lines: (typeof tokens)[] = [];
    for (const token of [...tokens].sort((a, b) => a.middle - b.middle)) {
      const line = lines.at(-1);
      if (line && Math.abs(line[0].middle - token.middle) <= 4)
        line.push(token);
      else lines.push([token]);
    }
    return {
      clippedWords,
      lines: lines.map((line) =>
        line
          .sort((a, b) => a.left - b.left)
          .map((token) => token.text)
          .join(" "),
      ),
    };
  });
}

/** Focuses a control from the keyboard and asserts no ancestor clips its focus ring. */
export async function expectUnclippedFocusRing(control: Locator) {
  await control.focus();
  await control.page().keyboard.press("Shift+Tab");
  await control.page().keyboard.press("Tab");
  await expect(control).toBeFocused();
  const clipped = await control.evaluate((element) => {
    const style = getComputedStyle(element);
    if (!element.matches(":focus-visible") || style.outlineStyle === "none")
      return "no focus ring";
    const reach =
      parseFloat(style.outlineWidth) + parseFloat(style.outlineOffset);
    const rect = element.getBoundingClientRect();
    const ring = {
      left: rect.left - reach,
      right: rect.right + reach,
      top: rect.top - reach,
      bottom: rect.bottom + reach,
    };
    for (let parent = element.parentElement; parent;) {
      const parentStyle = getComputedStyle(parent);
      const box = parent.getBoundingClientRect();
      const left = box.left + parent.clientLeft;
      const top = box.top + parent.clientTop;
      if (
        (parentStyle.overflowX !== "visible" &&
          (ring.left < left - 0.5 ||
            ring.right > left + parent.clientWidth + 0.5)) ||
        (parentStyle.overflowY !== "visible" &&
          (ring.top < top - 0.5 ||
            ring.bottom > top + parent.clientHeight + 0.5))
      )
        return `${element.textContent} is clipped by ${parent.tagName.toLowerCase()}.${parent.className}`;
      parent = parent.parentElement;
    }
    return null;
  });
  expect(clipped).toBeNull();
}

/** Asserts a dot-separated row never starts or ends a line with a separator. */
export async function expectSeparatorsBetweenWords(
  row: Locator,
  { lines: expectedLines }: { lines?: number } = {},
) {
  const { clippedWords, lines } = await readRenderedLines(row);
  const context = `rendered lines: ${JSON.stringify(lines)}`;
  expect(clippedWords, context).toEqual([]);
  expect(
    lines.filter((line) => line.startsWith("·") || line.endsWith("·")),
    context,
  ).toEqual([]);
  if (expectedLines !== undefined)
    expect(lines.length, context).toBe(expectedLines);
  return lines;
}
