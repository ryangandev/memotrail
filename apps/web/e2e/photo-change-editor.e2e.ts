import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import {
  test as base,
  expect,
  type Locator,
  type Page,
} from "@playwright/test";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import sharp from "sharp";
import { cleanupMediaFixture } from "./helpers/media-fixture";

// Photo changes leave the Entry's revision alone, so a page whose editor changed a
// photo can still move its Entry to Trash, while another device's writing still
// conflicts.
const test = base.extend<{
  account: { client: SupabaseClient; owner: string };
}>({
  account: async ({ context }, runTest) => {
    const env = JSON.parse(
      execFileSync("supabase", ["status", "-o", "json"], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }),
    );
    expect(env.API_URL).toBe("http://127.0.0.1:54321");
    const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });
    const created = await admin.auth.admin.createUser({
      email: `media-photo-change-${randomUUID()}@memotrail.local`,
      email_confirm: true,
    });
    expect(created.error).toBeNull();
    const owner = created.data.user!.id;
    try {
      const cookies: { name: string; value: string }[] = [];
      const client = createServerClient(env.API_URL, env.ANON_KEY, {
        cookies: {
          getAll: () => cookies,
          setAll: (values) => {
            cookies.push(...values.map(({ name, value }) => ({ name, value })));
          },
        },
      });
      const link = await admin.auth.admin.generateLink({
        type: "magiclink",
        email: created.data.user!.email!,
      });
      expect(link.error).toBeNull();
      const signedIn = await client.auth.verifyOtp({
        type: "magiclink",
        token_hash: link.data.properties!.hashed_token,
      });
      expect(signedIn.error).toBeNull();
      await context.addCookies(
        cookies.map((cookie) => ({
          ...cookie,
          domain: "127.0.0.1",
          path: "/",
          sameSite: "Lax" as const,
        })),
      );
      await runTest({ client, owner });
    } finally {
      await cleanupMediaFixture(admin, owner, env.API_URL);
    }
  },
});

async function createChapter(client: SupabaseClient, title: string) {
  const saved = await client.rpc("save_entry", {
    p_entry_id: randomUUID(),
    p_expected_revision: null,
    p_title: title,
    p_body: "Original writing",
    p_body_rich: null,
    p_tag_names: [],
    p_occurred_start: "2017-07-08T12:00:00Z",
    p_occurred_end: null,
    p_date_precision: "day",
    p_occurred_label: null,
    p_occurred_timezone: "UTC",
    p_primary_location: null,
    p_photo_location: null,
    p_is_chapter: true,
    p_is_first_time: false,
  });
  expect(saved.error).toBeNull();
  return saved.data[0].entry_id as string;
}

async function photo() {
  return sharp({
    create: { width: 40, height: 24, channels: 3, background: "#316652" },
  })
    .png()
    .toBuffer();
}

async function entryRow(client: SupabaseClient, entry: string) {
  const { data, error } = await client
    .from("entries")
    .select("revision,deleted_at")
    .eq("id", entry)
    .single();
  expect(error).toBeNull();
  return data!;
}

async function currentPhotos(client: SupabaseClient, entry: string) {
  const { data, error } = await client
    .from("attachments")
    .select("id")
    .eq("entry_id", entry)
    .eq("variant", "original")
    .is("deleted_at", null);
  expect(error).toBeNull();
  return data!.length;
}

function openEditorButton(page: Page) {
  return page.getByRole("button", { name: "Edit Chapter", exact: true });
}

/** Adds one photo through the Entry editor, then reopens the editor. */
async function openWithSavedPhoto(
  page: Page,
  client: SupabaseClient,
  entry: string,
) {
  await page.goto(`/items/${entry}`);
  await openEditorButton(page).click();
  const editor = page.getByRole("dialog", { name: "Edit Entry" });
  await editor.locator('input[type="file"]').setInputFiles({
    name: "kept.png",
    mimeType: "image/png",
    buffer: await photo(),
  });
  await editor
    .getByRole("button", { name: "Save changes", exact: true })
    .click();
  await expect(editor).toHaveCount(0);
  await expect.poll(() => currentPhotos(client, entry)).toBe(1);
  // The page shows the saved photo once it refreshes.
  await expect(
    page.getByRole("button", { name: "Open kept.png", exact: true }),
  ).toBeVisible();
  await openEditorButton(page).click();
  await expect(
    editor.getByRole("button", { name: "Remove kept.png", exact: true }),
  ).toBeVisible();
  return { editor, opened: (await entryRow(client, entry)).revision };
}

async function removePhoto(page: Page, editor: Locator) {
  await editor
    .getByRole("button", { name: "Remove kept.png", exact: true })
    .click();
  await page
    .getByRole("dialog", { name: "Move this photo to Trash?" })
    .getByRole("button", { name: "Move photo to Trash", exact: true })
    .click();
  await expect(
    editor.getByRole("button", { name: "Remove kept.png", exact: true }),
  ).toHaveCount(0);
}

async function closeEditor(editor: Locator) {
  await editor.getByRole("button", { name: "Cancel", exact: true }).click();
  await expect(editor).toHaveCount(0);
}

async function moveToTrash(page: Page, title: string) {
  await page
    .getByRole("button", { name: "Move to Trash", exact: true })
    .click();
  await page
    .getByRole("dialog", { name: `Move “${title}” to Trash?` })
    .getByRole("button", { name: "Move to Trash", exact: true })
    .click();
}

test("Chapter moves to Trash after removing a photo in its editor", async ({
  page,
  account: { client },
}) => {
  const uiErrors: string[] = [];
  page.on("pageerror", (error) => uiErrors.push(error.message));
  const title = "Photo change chapter";
  const entry = await createChapter(client, title);
  const { editor, opened } = await openWithSavedPhoto(page, client, entry);

  await removePhoto(page, editor);
  await expect.poll(() => currentPhotos(client, entry)).toBe(0);
  expect((await entryRow(client, entry)).revision).toBe(opened);
  await closeEditor(editor);
  await moveToTrash(page, title);

  await expect(page).toHaveURL("/library");
  await expect(page.getByText(/changed on another device/)).toHaveCount(0);
  expect((await entryRow(client, entry)).deleted_at).not.toBeNull();
  expect(uiErrors).toEqual([]);
});

test("Chapter moves to Trash after a partial photo upload failure", async ({
  page,
  account: { client },
}) => {
  const title = "Photo change partial upload";
  const entry = await createChapter(client, title);
  let failed = false;
  await page.route("**/storage/v1/object/entry-media/**", async (route) => {
    if (!failed && route.request().method() === "POST") {
      failed = true;
      await route.abort("failed");
    } else await route.continue();
  });
  await page.goto(`/items/${entry}`);
  await openEditorButton(page).click();
  const editor = page.getByRole("dialog", { name: "Edit Entry" });
  const bytes = await photo();
  await editor.locator('input[type="file"]').setInputFiles([
    { name: "first.png", mimeType: "image/png", buffer: bytes },
    { name: "second.png", mimeType: "image/png", buffer: bytes },
  ]);
  await editor
    .getByRole("button", { name: "Save changes", exact: true })
    .click();

  await expect(editor.getByText(/1 photo could not be attached/)).toBeVisible();
  expect(await currentPhotos(client, entry)).toBe(1);
  await closeEditor(editor);
  await moveToTrash(page, title);

  await expect(page).toHaveURL("/library");
  expect((await entryRow(client, entry)).deleted_at).not.toBeNull();
});

test("Chapter Trash still refuses another device's writing after a photo removal", async ({
  page,
  account: { client },
}) => {
  const title = "Photo change conflict";
  const entry = await createChapter(client, title);
  const { editor } = await openWithSavedPhoto(page, client, entry);

  await removePhoto(page, editor);
  await closeEditor(editor);
  expect(
    (
      await client
        .from("entries")
        .update({ body: "Other device writing" })
        .eq("id", entry)
    ).error,
  ).toBeNull();
  await moveToTrash(page, title);

  await expect(
    page
      .getByRole("alert")
      .filter({ hasText: "This Entry changed on another device" }),
  ).toBeVisible();
  expect((await entryRow(client, entry)).deleted_at).toBeNull();
});
