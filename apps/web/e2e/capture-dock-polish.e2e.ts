import { test, expect } from "./helpers/workspace-test";

test("capture dock keeps focus tight and reopens without rebuilding the editor", async ({
  page,
  workspace,
}) => {
  expect(workspace.owner).toBeTruthy();
  await page.emulateMedia({ colorScheme: "dark" });
  await page.setViewportSize({ width: 1440, height: 960 });
  await page.goto("/library");
  const trigger = page.getByRole("button", { name: "New entry", exact: true });
  const dialog = page.getByRole("dialog", {
    name: "What’s on your mind?",
    exact: true,
  });
  const editor = dialog.getByRole("textbox", {
    name: "Entry text",
    exact: true,
  });
  await trigger.focus();
  const focusStyle = await trigger.evaluate((element) => {
    const style = getComputedStyle(element);
    return {
      offset: Number.parseFloat(style.outlineOffset),
      background: style.backgroundColor,
      reflection: style.backgroundImage,
    };
  });
  await trigger.click();
  await expect(editor).toBeFocused();
  await editor.fill("A draft that should open without a reset.");
  await editor.evaluate((element) =>
    element.setAttribute("data-editor-continuity", "kept"),
  );
  await editor.press("Escape");
  await expect(dialog).not.toBeVisible();
  await expect(trigger).toBeFocused();
  await trigger.screenshot({
    path: test.info().outputPath("memotrail-dock-focus-polish.png"),
  });
  await page.keyboard.press("ControlOrMeta+j");
  await expect(editor).toBeFocused();
  expect(
    focusStyle.offset,
    "focus ring touches the control instead of leaving an outer gap",
  ).toBeLessThanOrEqual(0);
  expect(
    focusStyle.reflection,
    "glass has a subtle reflective surface",
  ).not.toBe("none");
  await expect(editor).toHaveAttribute("data-editor-continuity", "kept");
  await expect(editor).toHaveText("A draft that should open without a reset.");
  await expect(
    dialog.getByRole("status", { name: "Preparing writing space" }),
  ).toHaveCount(0);
  for (let cycle = 0; cycle < 3; cycle++) {
    await editor.press("Escape");
    await expect(dialog).not.toBeVisible();
    await page.keyboard.press("ControlOrMeta+j");
    await expect(editor).toBeFocused();
    await expect(editor).toHaveAttribute("data-editor-continuity", "kept");
  }
  await page.screenshot({
    animations: "disabled",
    path: test.info().outputPath("memotrail-dock-glass-polish-dark.png"),
  });
  await editor.press("Escape");
  await expect(dialog).not.toBeVisible();
  await page.emulateMedia({ colorScheme: "light" });
  await trigger.screenshot({
    path: test.info().outputPath("memotrail-dock-glass-polish-light.png"),
  });
});

test("a retained composer picks up dashboard edits and can interrupt collapse", async ({
  page,
  workspace,
}) => {
  expect(workspace.owner).toBeTruthy();
  await page.goto("/");
  const dashboardEditor = page.getByRole("textbox", {
    name: "Entry text",
    exact: true,
  });
  const trigger = page.getByRole("button", { name: "New entry", exact: true });
  const dialog = page.getByRole("dialog", {
    name: "What’s on your mind?",
    exact: true,
  });
  const editor = dialog.getByRole("textbox", {
    name: "Entry text",
    exact: true,
  });
  await dashboardEditor.fill("First draft from the dashboard.");
  await trigger.click();
  await expect(editor).toHaveText("First draft from the dashboard.");
  await editor.press("Escape");
  await expect(dialog).not.toBeVisible();
  await dashboardEditor.fill("Latest draft from the dashboard.");
  await trigger.click();
  await expect(editor).toHaveText("Latest draft from the dashboard.");
  await dialog.getByRole("button", { name: "Close quick capture" }).click();
  await page.keyboard.press("ControlOrMeta+j");
  await expect(editor).toBeFocused();
  await expect(editor).toHaveText("Latest draft from the dashboard.");
  // A click waits for the reopened surface to settle and catches any stale
  // completion callback that would otherwise close it a second time.
  await editor.click();
  await expect(dialog).toBeVisible();
  await dialog.getByRole("button", { name: "Save", exact: true }).click();
  await expect(editor).toBeEmpty();
  await editor.press("Escape");
  await expect(dialog).not.toBeVisible();
  await trigger.click();
  await expect(editor).toBeEmpty();
});
