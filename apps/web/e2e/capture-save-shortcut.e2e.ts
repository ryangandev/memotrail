import { test, expect } from "./helpers/workspace-test";

test("capture saves with Command Return while Enter still writes another line", async ({
  page,
  workspace,
}) => {
  await page.goto("/");
  const editor = page.getByRole("textbox", { name: "Entry text", exact: true });
  await editor.fill("First line.");
  await editor.press("End");
  await editor.press("Enter");
  await editor.pressSequentially("Second line.");
  await editor.press("Shift+Enter");
  await editor.pressSequentially("A continuation.");
  await expect(editor.locator("p")).toHaveCount(2);
  await expect(editor.locator("br")).toHaveCount(1);
  const unsaved = await workspace.client
    .from("entries")
    .select("id")
    .eq("owner_id", workspace.owner);
  expect(unsaved.error).toBeNull();
  expect(unsaved.data).toHaveLength(0);
  await editor.dispatchEvent("keydown", {
    key: "Enter",
    metaKey: true,
    isComposing: true,
  });
  await expect(editor).toContainText("A continuation.");
  await expect(
    page.getByRole("button", { name: "Save to Inbox", exact: true }),
  ).toHaveAttribute("aria-keyshortcuts", "Meta+Enter Control+Enter");
  const save = page.getByRole("button", { name: "Save to Inbox", exact: true });
  const saveHint = page.getByRole("tooltip", {
    name: "Save to Inbox ⌘ Return",
  });
  await save.hover();
  await expect(saveHint).toBeVisible();
  await page.mouse.move(10, 10);
  await expect(saveHint).not.toBeVisible();
  await save.focus();
  await expect(saveHint).toBeVisible();
  await editor.focus();
  await expect(saveHint).not.toBeVisible();
  await editor.press("Meta+Enter");
  await expect
    .poll(async () => {
      const saved = await workspace.client
        .from("entries")
        .select("body,inbox_status")
        .eq("owner_id", workspace.owner);
      expect(saved.error).toBeNull();
      return saved.data;
    })
    .toEqual([
      expect.objectContaining({
        body: expect.stringMatching(
          /First line\.\s+Second line\.\s+A continuation\./,
        ),
        inbox_status: "unreviewed",
      }),
    ]);
  await expect(editor).toBeEmpty();

  await page.getByRole("button", { name: "New entry", exact: true }).click();
  const dialog = page.getByRole("dialog", { name: "What’s on your mind?" });
  const dockEditor = dialog.getByRole("textbox", {
    name: "Entry text",
    exact: true,
  });
  await dialog
    .getByRole("button", { name: "Save to Inbox", exact: true })
    .hover();
  await expect(
    dialog.getByRole("tooltip", { name: "Save to Inbox ⌘ Return" }),
  ).toBeVisible();
  await dockEditor.fill("A linked draft");
  await dockEditor.press("Meta+a");
  await dockEditor.press("Meta+k");
  const linkEditor = dialog.getByRole("group", {
    name: "Link editor",
    exact: true,
  });
  await linkEditor
    .getByLabel("Link URL", { exact: true })
    .fill("mailto:hello@example.com");
  await linkEditor.getByLabel("Link URL", { exact: true }).press("Meta+Enter");
  await expect(linkEditor).not.toBeVisible();
  await expect(dockEditor.locator("a")).toHaveAttribute(
    "href",
    "mailto:hello@example.com",
  );
  const afterLinkEdit = await workspace.client
    .from("entries")
    .select("id")
    .eq("owner_id", workspace.owner);
  expect(afterLinkEdit.error).toBeNull();
  expect(afterLinkEdit.data).toHaveLength(1);

  await dockEditor.press("Meta+a");
  await dockEditor.press("Meta+k");
  await linkEditor
    .getByLabel("Link URL", { exact: true })
    .fill("tel:+15555550123");
  await linkEditor.getByLabel("Link URL", { exact: true }).press("Enter");
  await expect(dockEditor.locator("a")).toHaveAttribute(
    "href",
    "tel:+15555550123",
  );
  await dockEditor.fill("A code line");
  await dialog.getByRole("button", { name: "Code block", exact: true }).click();
  await dockEditor.press("End");
  await dockEditor.press("Enter");
  await dockEditor.pressSequentially("Another code line");
  await expect(dockEditor.locator("pre code")).toContainText(
    "Another code line",
  );
  await dockEditor.focus();
  await page.keyboard.down("Control");
  await page.keyboard.down("Enter");
  await page.keyboard.down("Enter");
  await page.keyboard.up("Enter");
  await page.keyboard.up("Control");
  await expect
    .poll(async () => {
      const saved = await workspace.client
        .from("entries")
        .select("body")
        .eq("owner_id", workspace.owner);
      expect(saved.error).toBeNull();
      return saved.data?.length;
    })
    .toBe(2);
  await expect(dockEditor).toBeEmpty();
  await expect(dockEditor.locator("p")).toHaveCount(1);
  await expect(dockEditor.locator("br")).toHaveCount(1);
});
