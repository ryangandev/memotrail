import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect, type BrowserContext, type Page } from "@playwright/test";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import sharp from "sharp";
import { sql } from "./helpers/database";
import { cleanupMediaFixture } from "./helpers/media-fixture";

// The first visit can compile the Trash route and its Server Actions.
const firstCompile = { timeout: 90_000 };

type Account = {
  admin: SupabaseClient;
  client: SupabaseClient;
  owner: string;
  photoEntry: (title: string) => Promise<{ entry: string; path: string }>;
};

/** Counts every Storage object of one Entry, including generated previews. */
function entryObjects(owner: string, entry: string) {
  return Number(
    sql(
      `select count(*) from storage.objects where bucket_id='entry-media' and starts_with(name,'${owner}/${entry}/')`,
    ),
  );
}

function recordedPurges(owner: string) {
  return Number(
    sql(`select count(*) from public.media_purges where owner_id='${owner}'`),
  );
}

async function withAccount(
  context: BrowserContext,
  run: (account: Account) => Promise<void>,
) {
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
  const email = `media-trash-purge-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
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
      email,
    });
    expect(
      (
        await client.auth.verifyOtp({
          type: "magiclink",
          token_hash: link.data.properties!.hashed_token,
        })
      ).error,
    ).toBeNull();
    await context.addCookies(
      cookies.map((cookie) => ({
        ...cookie,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax" as const,
      })),
    );
    const bytes = await sharp({
      create: { width: 24, height: 24, channels: 3, background: "#316652" },
    })
      .png()
      .toBuffer();
    await run({
      admin,
      client,
      owner,
      async photoEntry(title) {
        const entry = randomUUID(),
          attachment = randomUUID();
        const path = `${owner}/${entry}/${attachment}.png`;
        expect(
          (
            await client
              .from("entries")
              .insert({ id: entry, owner_id: owner, title })
          ).error,
        ).toBeNull();
        expect(
          (
            await client.storage
              .from("entry-media")
              .upload(path, bytes, { contentType: "image/png" })
          ).error,
        ).toBeNull();
        expect(
          (
            await client.rpc("register_entry_attachment", {
              p_entry_id: entry,
              p_attachment_id: attachment,
              p_object_path: path,
              p_original_filename: "trail.png",
              p_mime_type: "image/png",
              p_byte_size: bytes.length,
              p_pixel_width: 24,
              p_pixel_height: 24,
            })
          ).error,
        ).toBeNull();
        expect(
          (
            await client
              .from("entries")
              .update({ deleted_at: new Date().toISOString() })
              .eq("id", entry)
          ).error,
        ).toBeNull();
        return { entry, path };
      },
    });
  } finally {
    await cleanupMediaFixture(admin, owner, env.API_URL);
  }
}

const card = (page: Page, title: string) =>
  page.getByRole("article").filter({ hasText: title });

const toast = (page: Page, text: string) =>
  page.locator("[data-sonner-toast]").filter({ hasText: text });

/** Opens the Delete forever confirmation, retrying a click made before hydration. */
async function confirmDeletion(page: Page, title: string) {
  const dialog = page.getByRole("dialog");
  await expect(async () => {
    if (!(await dialog.isVisible())) {
      await card(page, title)
        .getByRole("button", { name: "Delete forever", exact: true })
        .click();
    }
    await expect(dialog).toBeVisible({ timeout: 2_000 });
  }).toPass(firstCompile);
  await expect(dialog).toContainText(`Delete “${title}” forever?`);
  return dialog;
}

test("Delete forever removes photo files only after the record, and Trash finishes an interrupted removal", async ({
  page,
  context,
}) => {
  test.setTimeout(180_000);
  await withAccount(context, async ({ client, owner, photoEntry }) => {
    const shown = await photoEntry("Ridge photo deleted in Trash");
    const interrupted = await photoEntry("Lake photo left by a lost request");
    // A Delete forever whose file removal never ran: the record is the commit point.
    const row = await client
      .from("entries")
      .select("revision,deleted_at")
      .eq("id", interrupted.entry)
      .single();
    expect(row.error).toBeNull();
    const params = {
      p_item_kind: "entry",
      p_item_id: interrupted.entry,
      p_expected_revision: row.data!.revision,
      p_expected_deleted_at: row.data!.deleted_at,
    };
    expect(
      (await client.rpc("delete_trash_item_forever", params)).data,
    ).toHaveLength(1);
    expect(entryObjects(owner, interrupted.entry)).toBe(1);
    expect(recordedPurges(owner)).toBe(1);
    expect((await client.rpc("restore_trash_item", params)).data).toEqual([]);

    await page.goto("/trash");
    await expect(card(page, "Ridge photo deleted in Trash")).toBeVisible();
    await expect(card(page, "Lake photo left by a lost request")).toHaveCount(
      0,
    );
    // Opening Trash finishes the earlier removal without any user action.
    await expect
      .poll(() => entryObjects(owner, interrupted.entry), firstCompile)
      .toBe(0);
    await expect.poll(() => recordedPurges(owner)).toBe(0);

    const image = card(page, "Ridge photo deleted in Trash").locator(
      'img[src*="/api/media/image"]',
    );
    await expect
      .poll(
        () =>
          image.evaluate(
            (img: HTMLImageElement) => img.complete && img.naturalWidth > 0,
          ),
        firstCompile,
      )
      .toBe(true);
    const dialog = await confirmDeletion(page, "Ridge photo deleted in Trash");
    await dialog
      .getByRole("button", { name: "Delete forever", exact: true })
      .click();
    // Exact text: the removal finished, so no pending-files notice is added.
    await expect(
      page.getByText("Item permanently deleted.", { exact: true }),
    ).toBeVisible(firstCompile);
    await expect(card(page, "Ridge photo deleted in Trash")).toHaveCount(0);
    expect(
      (await client.from("entries").select("id").eq("id", shown.entry)).data,
    ).toEqual([]);
    // The original and any generated preview are gone, and nothing stays recorded.
    expect(entryObjects(owner, shown.entry)).toBe(0);
    expect(recordedPurges(owner)).toBe(0);
  });
});

test("Restore refuses missing originals, and a stale Delete forever cannot remove a restored photo", async ({
  page,
  context,
}) => {
  test.setTimeout(180_000);
  await withAccount(context, async ({ admin, client, owner, photoEntry }) => {
    const missing = await photoEntry("Summit photo with a missing original");
    const restored = await photoEntry("Harbor photo restored elsewhere");
    expect(
      (await admin.storage.from("entry-media").remove([missing.path])).error,
    ).toBeNull();

    await page.goto("/trash");
    await expect(card(page, "Harbor photo restored elsewhere")).toBeVisible();
    // Both desktop actions keep one-line labels at the same height.
    const actions = card(page, "Harbor photo restored elsewhere").getByRole(
      "button",
    );
    const restoreBox = await actions.nth(0).boundingBox();
    const deleteBox = await actions.nth(1).boundingBox();
    expect(deleteBox!.height).toBe(restoreBox!.height);
    const dialog = await confirmDeletion(
      page,
      "Harbor photo restored elsewhere",
    );
    // Another device restores it while this confirmation is open.
    expect(
      (
        await client
          .from("entries")
          .update({ deleted_at: null })
          .eq("id", restored.entry)
      ).error,
    ).toBeNull();
    await dialog
      .getByRole("button", { name: "Delete forever", exact: true })
      .click();
    await expect(
      toast(
        page,
        "This item changed on another device. Refresh before trying again.",
      ),
    ).toBeVisible(firstCompile);
    expect(
      sql(
        `select count(*) from storage.objects where bucket_id='entry-media' and name='${restored.path}'`,
      ),
    ).toBe("1");
    expect(recordedPurges(owner)).toBe(0);
    expect(
      (
        await client
          .from("entries")
          .select("deleted_at")
          .eq("id", restored.entry)
          .single()
      ).data,
    ).toEqual({ deleted_at: null });
    await dialog.getByRole("button", { name: "Cancel", exact: true }).click();
    await expect(dialog).toBeHidden();

    await card(page, "Summit photo with a missing original")
      .getByRole("button", { name: "Restore", exact: true })
      .click();
    await expect(
      toast(
        page,
        "This item's original photos are missing, so it cannot be restored. You can still delete it forever.",
      ),
    ).toBeVisible();
    await expect(
      card(page, "Summit photo with a missing original"),
    ).toBeVisible();
    expect(
      (
        await client
          .from("entries")
          .select("deleted_at")
          .eq("id", missing.entry)
          .single()
      ).data?.deleted_at,
    ).not.toBeNull();

    const missingDialog = await confirmDeletion(
      page,
      "Summit photo with a missing original",
    );
    await missingDialog
      .getByRole("button", { name: "Delete forever", exact: true })
      .click();
    await expect(
      page.getByText("Item permanently deleted.", { exact: true }),
    ).toBeVisible();
    await expect(
      card(page, "Summit photo with a missing original"),
    ).toHaveCount(0);
    expect(entryObjects(owner, missing.entry)).toBe(0);
    expect(recordedPurges(owner)).toBe(0);
  });
});
