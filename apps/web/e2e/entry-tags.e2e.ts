import { randomUUID } from "node:crypto";
import type { Locator, Page } from "@playwright/test";
import { expect, test } from "./helpers/workspace-test";

async function follows(earlier: Locator, later: Locator) {
  return earlier.evaluate(
    (element, next) =>
      Boolean(
        element.compareDocumentPosition(next as Node) &
        Node.DOCUMENT_POSITION_FOLLOWING,
      ),
    await later.elementHandle(),
  );
}

async function expectNoHorizontalScroll(page: Page) {
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBe(true);
}

test("The Entry editor puts tags first and reuses existing tags", async ({
  page,
  workspace: { client, owner },
}) => {
  const uiErrors: string[] = [];
  page.on("pageerror", (error) => uiErrors.push(error.message));
  const entryId = randomUUID();
  const tags = {
    books: randomUUID(),
    family: randomUUID(),
    purged: randomUUID(),
    trashed: randomUUID(),
    travel: randomUUID(),
    unused: randomUUID(),
  };
  expect(
    (
      await client
        .from("profiles")
        .update({ timezone: "America/New_York" })
        .eq("user_id", owner)
    ).error,
  ).toBeNull();
  // Travel is used most, then family and books. The Entries using "archived" are in
  // Trash and the one using "purged" is deleted forever below, so both count as
  // unused, like "unused", which never had an Entry.
  const usage = [
    ["travel", 3, null],
    ["family", 2, null],
    ["books", 1, null],
    ["trashed", 4, new Date().toISOString()],
    ["purged", 1, new Date().toISOString()],
  ] as const;
  const entries = usage.flatMap(([tag, count, deletedAt]) =>
    Array.from({ length: count }, (_, index) => ({
      deleted_at: deletedAt,
      id: randomUUID(),
      owner_id: owner,
      tag,
      title: `${tag} ${index + 1}`,
    })),
  );
  expect(
    (
      await client.from("tags").insert([
        { id: tags.travel, owner_id: owner, name: "Travel" },
        { id: tags.family, owner_id: owner, name: "family" },
        { id: tags.books, owner_id: owner, name: "books" },
        { id: tags.trashed, owner_id: owner, name: "archived" },
        { id: tags.purged, owner_id: owner, name: "purged" },
        { id: tags.unused, owner_id: owner, name: "unused" },
      ])
    ).error,
  ).toBeNull();
  expect(
    (
      await client.from("entries").insert([
        ...entries.map((entry) => ({
          body: "",
          date_precision: "unknown",
          deleted_at: entry.deleted_at,
          id: entry.id,
          occurred_start: null,
          occurred_timezone: null,
          owner_id: owner,
          title: entry.title,
        })),
        {
          body: "Walked along the river before work.",
          date_precision: "exact",
          deleted_at: null,
          id: entryId,
          occurred_start: "2026-06-12T11:30:00+00:00",
          occurred_timezone: "America/New_York",
          owner_id: owner,
          title: "Morning walk",
        },
      ])
    ).error,
  ).toBeNull();
  expect(
    (
      await client.from("entry_tags").insert(
        entries.map((entry) => ({
          entry_id: entry.id,
          owner_id: owner,
          tag_id: tags[entry.tag],
        })),
      )
    ).error,
  ).toBeNull();
  const purged = entries.find((entry) => entry.tag === "purged")!;
  const { data: trashed } = await client
    .from("entries")
    .select("revision,deleted_at")
    .eq("id", purged.id)
    .single();
  const deleted = await client.rpc("delete_trash_item_forever", {
    p_expected_deleted_at: trashed!.deleted_at,
    p_expected_revision: trashed!.revision,
    p_item_id: purged.id,
    p_item_kind: "entry",
  });
  expect(deleted.error).toBeNull();
  expect(deleted.data).toHaveLength(1);
  expect(
    (
      await client
        .from("entry_tags")
        .select("tag_id", { count: "exact", head: true })
        .eq("tag_id", tags.purged)
    ).count,
  ).toBe(0);

  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto(`/items/${entryId}`);
  await page.getByRole("button", { name: "Edit Entry", exact: true }).click();
  const editor = page.getByRole("dialog", { name: "Edit Entry" });
  await expect(
    editor.getByRole("heading", { name: "Edit Entry", exact: true }),
  ).toBeVisible();
  await expect(editor.getByText("Life Wiki editor")).toHaveCount(0);

  // Title, Note, Tags, then Photos and the rest.
  const order = [
    editor.getByRole("textbox", { name: "Title", exact: true }),
    editor.getByRole("textbox", { name: "Note", exact: true }),
    editor.getByRole("group", { name: "Tags", exact: true }),
    editor.getByRole("group", { name: "Photos", exact: true }),
    editor.getByRole("group", { name: "Date", exact: true }),
  ];
  for (let index = 1; index < order.length; index++)
    expect(await follows(order[index - 1], order[index])).toBe(true);

  // An exact time in the Settings time zone names the zone instead of a select.
  await expect(
    editor.getByRole("combobox", { name: "Time zone", exact: true }),
  ).toHaveCount(0);
  await expect(
    editor.getByRole("group", { name: "Time zone", exact: true }),
  ).toHaveText(/Default from Settings\(UTC-04:00\) New York - America/);

  // An Entry without tags offers the most used ones. Trash does not count, and tags
  // without any Entry are still offered, last and by name.
  const suggestions = editor.getByRole("group", { name: "Most used tags" });
  await expect(suggestions.getByRole("button")).toHaveText([
    "Travel",
    "family",
    "books",
    "archived",
    "purged",
    "unused",
  ]);
  await expect(editor.getByText(/of 70/)).toHaveCount(0);
  await page.screenshot({
    animations: "disabled",
    caret: "initial",
    path: test.info().outputPath("memotrail-entry-tags-desktop.png"),
  });

  // Reusing a tag takes one click, and the rest stay offered.
  await suggestions.getByRole("button", { name: "Add tag family" }).click();
  await expect(
    editor.getByRole("button", { name: "Remove family from Tags" }),
  ).toBeVisible();
  const tagInput = editor.getByRole("combobox", { name: "Tags", exact: true });
  await expect(tagInput).toBeFocused();
  await expect(suggestions.getByRole("button")).toHaveText([
    "Travel",
    "books",
    "archived",
    "purged",
    "unused",
  ]);

  // A name that differs only by case is the existing tag, not a new one.
  await tagInput.fill("travel");
  const options = editor.getByRole("listbox");
  await expect(options.getByRole("option")).toHaveCount(1);
  await expect(options.getByRole("option")).toContainText("Existing tag");
  await expect(options.getByText("Create tag")).toHaveCount(0);
  await page.screenshot({
    animations: "disabled",
    caret: "initial",
    path: test.info().outputPath("memotrail-entry-tags-options.png"),
  });
  await tagInput.press("Enter");
  await expect(
    editor.getByRole("button", { name: "Remove Travel from Tags" }),
  ).toBeVisible();
  await expect(tagInput).toHaveValue("");

  // A name typed but not added is saved too, written as its existing tag.
  await tagInput.fill("BOOKS");
  await page.setViewportSize({ width: 390, height: 844 });
  await page.emulateMedia({ colorScheme: "dark" });
  await editor
    .getByRole("group", { name: "Tags", exact: true })
    .scrollIntoViewIfNeeded();
  await page.screenshot({
    animations: "disabled",
    caret: "initial",
    path: test.info().outputPath("memotrail-entry-tags-mobile.png"),
  });
  await expectNoHorizontalScroll(page);
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.emulateMedia({ colorScheme: "light" });
  await editor.getByRole("button", { name: "Save changes" }).click();
  await expect(editor).toHaveCount(0);

  const saved = await client
    .from("entry_tags")
    .select("tag_id")
    .eq("entry_id", entryId);
  expect(saved.error).toBeNull();
  expect(saved.data!.map((row) => row.tag_id).sort()).toEqual(
    [tags.books, tags.family, tags.travel].sort(),
  );
  const ownerTags = await client
    .from("tags")
    .select("name")
    .eq("owner_id", owner);
  expect(ownerTags.data!.map((row) => row.name).sort()).toEqual(
    ["Travel", "archived", "books", "family", "purged", "unused"].sort(),
  );
  await expect(
    page.getByRole("article", { name: "Entry", exact: true }),
  ).toContainText("Travel");
  expect(uiErrors).toEqual([]);
});
