import { randomUUID } from "node:crypto";
import { test, expect } from "./helpers/workspace-test";

const boldDocument = (text: string) => ({
  content: [
    {
      content: [{ marks: [{ type: "bold" }], text, type: "text" }],
      type: "paragraph",
    },
  ],
  type: "doc",
});

test("capture keeps formatting when the note ends with a new line", async ({
  page,
  workspace,
}) => {
  await page.goto("/");
  const capture = page.getByRole("form", {
    name: "Quick capture",
    exact: true,
  });
  const editor = capture.getByRole("textbox", {
    name: "Entry text",
    exact: true,
  });
  await editor.click();
  await editor.press("Meta+b");
  await editor.pressSequentially("Bold capture");
  await expect(editor.locator("strong")).toHaveText("Bold capture");
  await editor.press("Enter");
  await editor.press("Enter");
  await editor.pressSequentially("  ");
  await expect(editor.locator("p")).toHaveCount(3);
  // The draft keeps exactly what the editor shows until the capture is saved.
  await expect
    .poll(() =>
      page.evaluate((owner) => {
        const stored = localStorage.getItem(`memotrail:inbox-draft:${owner}`);
        return stored ? JSON.parse(stored) : null;
      }, workspace.owner),
    )
    .toMatchObject({
      body: "Bold capture\n\n  ",
      bodyRich: { text: "Bold capture\n\n  ", version: 1 },
    });

  await capture
    .getByRole("button", { name: "Save to Inbox", exact: true })
    .click();
  await expect(
    page.locator("[data-sonner-toast]").filter({ hasText: "Saved to Inbox." }),
  ).toBeVisible();
  await expect(editor).toBeEmpty();
  await expect
    .poll(async () => {
      const saved = await workspace.client
        .from("entries")
        .select("body,metadata")
        .eq("owner_id", workspace.owner);
      expect(saved.error).toBeNull();
      return saved.data;
    })
    .toEqual([
      {
        body: "Bold capture",
        metadata: {
          body_rich: {
            document: boldDocument("Bold capture"),
            text: "Bold capture",
            version: 1,
          },
        },
      },
    ]);

  await page.goto("/inbox");
  const card = page
    .getByRole("article")
    .filter({ has: page.getByRole("heading", { name: "Bold capture" }) });
  await card.getByRole("button", { name: "Organize", exact: true }).click();
  const review = page.getByRole("dialog", { name: "Review Entry" });
  await expect(
    review
      .getByRole("textbox", { name: "Note", exact: true })
      .locator("strong"),
  ).toHaveText("Bold capture");
});

test("Inbox review saves a formatted note with surrounding whitespace", async ({
  page,
  workspace,
}) => {
  const id = randomUUID();
  const inserted = await workspace.client.from("entries").insert({
    body: "Bold review note",
    date_precision: "exact",
    id,
    inbox_status: "unreviewed",
    item_kind: "entry",
    item_subtype: "entry",
    metadata: {
      body_rich: {
        document: boldDocument("Bold review note"),
        text: "Bold review note",
        version: 1,
      },
    },
    occurred_start: "2026-09-30T08:15:00Z",
    occurred_timezone: "UTC",
    owner_id: workspace.owner,
    title: "Formatted review",
  });
  expect(inserted.error).toBeNull();

  await page.goto("/inbox");
  const card = page
    .getByRole("article")
    .filter({ has: page.getByRole("heading", { name: "Formatted review" }) });
  await card.getByRole("button", { name: "Organize", exact: true }).click();
  const review = page.getByRole("dialog", { name: "Review Entry" });
  const note = review.getByRole("textbox", { name: "Note", exact: true });
  await expect(note.locator("strong")).toHaveText("Bold review note");
  await note.click();
  await note.press("Meta+ArrowUp");
  await note.pressSequentially("  ");
  await note.press("Meta+ArrowDown");
  await note.press("Enter");
  await note.pressSequentially(" ");
  await expect(note.locator("p")).toHaveCount(2);

  await review
    .getByRole("button", { name: "Save changes", exact: true })
    .click();
  await expect(review).not.toBeVisible();
  await expect(
    page.locator("[data-sonner-toast]").filter({ hasText: "Entry saved." }),
  ).toBeVisible();
  const saved = await workspace.client
    .from("entries")
    .select("body,inbox_status,metadata,revision")
    .eq("id", id)
    .single();
  expect(saved.error).toBeNull();
  expect(saved.data).toEqual({
    body: "Bold review note",
    inbox_status: "unreviewed",
    metadata: {
      body_rich: {
        document: boldDocument("Bold review note"),
        text: "Bold review note",
        version: 1,
      },
    },
    revision: 2,
  });

  await card.getByRole("button", { name: "Organize", exact: true }).click();
  await expect(note.locator("strong")).toHaveText("Bold review note");
  await expect(note.locator("p")).toHaveCount(1);
});
