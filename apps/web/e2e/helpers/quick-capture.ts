import type { Page } from "@playwright/test";

// The Dashboard holds its own composer, so its dock is search only and Quick Capture opens
// from the keyboard there. The shortcut ignores editable targets, so the focused editor
// lets go first.
export async function openQuickCaptureByShortcut(page: Page) {
  await page.evaluate(() => {
    if (document.activeElement instanceof HTMLElement)
      document.activeElement.blur();
  });
  await page.keyboard.press("ControlOrMeta+j");
}
