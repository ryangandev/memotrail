import type { Page } from "@playwright/test";
import { expect, test } from "./helpers/workspace-test";

// The acceptance guard for capture: recording a thought takes opening the
// composer, writing, and Command Return, with nothing to fill in or choose.
for (const opening of ["the dock", "Command J"] as const) {
  test(`a capture opened from ${opening} saves without a decision`, async ({
    page,
    workspace,
  }) => {
    const nativeDialogs: string[] = [];
    page.on("dialog", (dialog) => {
      nativeDialogs.push(dialog.message());
      void dialog.dismiss();
    });
    await page.goto("/library");
    await watchInterruptions(page);
    const composer = page.getByRole("dialog", { name: "What’s on your mind?" });
    const text = composer.getByRole("textbox", {
      name: "Entry text",
      exact: true,
    });

    if (opening === "the dock")
      await page
        .getByRole("button", { name: "New entry", exact: true })
        .click();
    else
      // Command J works once the workspace has hydrated.
      await expect(async () => {
        await page.keyboard.press("ControlOrMeta+j");
        await expect(text).toBeFocused({ timeout: 1000 });
      }).toPass({ timeout: 30_000 });
    // The writing field is ready and focused, so typing needs no click.
    await expect(text).toBeFocused({ timeout: 30_000 });

    // Nothing is required, and there is no title, type, or option to settle.
    await expect(
      composer.locator("[required], [aria-required='true']"),
    ).toHaveCount(0);
    await expect(composer.getByRole("textbox")).toHaveCount(1);
    for (const role of [
      "checkbox",
      "combobox",
      "listbox",
      "radio",
      "radiogroup",
    ] as const)
      await expect(composer.getByRole(role)).toHaveCount(0);

    const body = `Remembered on the walk home, from ${opening}`;
    await page.keyboard.type(body);
    await page.keyboard.press("ControlOrMeta+Enter");

    await expect
      .poll(async () => {
        const saved = await workspace.client
          .from("entries")
          .select("body,title,date_precision,occurred_start,deleted_at");
        expect(saved.error).toBeNull();
        return saved.data;
      })
      .toEqual([
        expect.objectContaining({
          body,
          title: null,
          date_precision: "exact",
          occurred_start: expect.any(String),
          deleted_at: null,
        }),
      ]);
    // The composer empties for the next thought and reports no problem.
    await expect(text).toBeEmpty();
    await expect(composer.getByRole("alert")).toHaveCount(0);
    await expect(
      composer.locator("[required], [aria-required='true']"),
    ).toHaveCount(0);
    // Nothing else opened on the way: no dialog, menu, or list to answer.
    expect(await interruptions(page)).toEqual([]);
    expect(nativeDialogs).toEqual([]);
  });
}

/**
 * Records any dialog, menu, or option list that becomes visible, other than
 * the Quick Capture dialog itself.
 */
async function watchInterruptions(page: Page) {
  await page.evaluate(() => {
    const seen: string[] = [];
    (window as unknown as { interruptions: string[] }).interruptions = seen;
    const selector =
      "dialog[open], [role='dialog'], [role='alertdialog'], [role='menu'], [role='listbox']";
    const record = () => {
      for (const element of document.querySelectorAll(selector)) {
        if (
          element.querySelector("[data-ui-capture-composer]") ||
          !element.checkVisibility()
        )
          continue;
        const name =
          element.getAttribute("aria-label") ??
          element.textContent?.trim().slice(0, 60) ??
          element.tagName;
        if (!seen.includes(name)) seen.push(name);
      }
    };
    new MutationObserver(record).observe(document.body, {
      attributes: true,
      childList: true,
      subtree: true,
    });
  });
}

function interruptions(page: Page) {
  return page.evaluate(
    () => (window as unknown as { interruptions: string[] }).interruptions,
  );
}
