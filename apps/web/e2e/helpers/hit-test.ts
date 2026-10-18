import type { Locator } from "@playwright/test";

/**
 * Whether a pointer at the control's center reaches the control itself, so
 * nothing, such as a native modal dialog in the top layer, covers it.
 */
export async function isTopmostAtCenter(control: Locator) {
  return control.evaluate((element) => {
    const box = element.getBoundingClientRect();
    const hit = document.elementFromPoint(
      box.left + box.width / 2,
      box.top + box.height / 2,
    );
    return hit !== null && element.contains(hit);
  });
}
