import { test, expect } from "./helpers/workspace-test";
import { openQuickCaptureByShortcut } from "./helpers/quick-capture";

test("sidebar shortcuts persist and leave editor bold shortcuts alone", async ({
  page,
  workspace,
}) => {
  expect(workspace.owner).toBeTruthy();
  await page.goto("/");
  const editor = page.getByRole("textbox", { name: "Entry text", exact: true });
  await expect(editor).toBeVisible();
  const toggle = page.getByRole("button", {
    name: "Collapse sidebar",
    exact: true,
  });
  await expect(toggle).toHaveAttribute(
    "title",
    "Collapse sidebar (⌘ B / Ctrl+B)",
  );
  await toggle.focus();
  await page.keyboard.press("ControlOrMeta+b");
  await expect(
    page.getByRole("button", { name: "Expand sidebar" }),
  ).toBeVisible();
  await page.reload();
  await expect(editor).toBeVisible();
  await page.getByRole("button", { name: "Expand sidebar" }).focus();
  await page.keyboard.press("Control+b");
  await expect(toggle).toBeVisible();

  await editor.fill("Keep this bold");
  await editor.press("ControlOrMeta+a");
  await editor.press("ControlOrMeta+b");
  await expect(editor.locator("strong")).toHaveText("Keep this bold");
  await expect(toggle).toBeVisible();

  await openQuickCaptureByShortcut(page);
  const dialog = page.getByRole("dialog", { name: "What’s on your mind?" });
  const dialogEditor = dialog.getByRole("textbox", {
    name: "Entry text",
    exact: true,
  });
  await expect(dialogEditor.locator("strong")).toHaveText("Keep this bold");
  await dialogEditor.press("ControlOrMeta+a");
  await dialogEditor.press("ControlOrMeta+b");
  await expect(dialogEditor.locator("strong")).toHaveCount(0);
  await dialog.getByRole("button", { name: "Close quick capture" }).click();
  await expect(toggle).toBeVisible();

  await page
    .getByRole("button", { name: "Search everything", exact: true })
    .click();
  await page
    .getByRole("searchbox", { name: "Search MemoTrail" })
    .press("ControlOrMeta+b");
  await page.keyboard.press("Escape");
  await expect(toggle).toBeVisible();
  await toggle.focus();
  await page.keyboard.press("ControlOrMeta+Shift+b");
  await expect(toggle).toBeVisible();
  await page.setViewportSize({ width: 390, height: 844 });
  await page.getByRole("link", { name: "MemoTrail dashboard" }).last().focus();
  await page.keyboard.press("ControlOrMeta+b");
  await expect(page.locator("[data-sidebar-collapsed]")).toHaveAttribute(
    "data-sidebar-collapsed",
    "false",
  );
});
