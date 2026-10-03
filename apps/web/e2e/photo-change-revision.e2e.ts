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

// Photo changes create their own Entry revision. An editor opened before one
// must still trash or achieve its record, while another device's writing must not
// be silently adopted.
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
      email: `media-revision-${randomUUID()}@memotrail.local`,
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

const common = {
  p_body: "Original writing",
  p_collection_names: [],
  p_entry_id: null,
  p_expected_revision: null,
  p_tag_names: [],
};
const dates = {
  p_date_precision: "day",
  p_occurred_end: null,
  p_occurred_label: null,
  p_occurred_start: "2017-07-08T12:00:00Z",
  p_occurred_timezone: "UTC",
};
const goal = {
  ...common,
  p_horizon: "someday",
  p_related_entry_ids: [],
  p_status: "active",
  p_target_date: null,
};
const records = {
  goal: {
    label: "Goal",
    path: "/goals",
    rpc: "save_goal_entry",
    args: goal,
  },
  home: {
    label: "Home",
    path: "/homes",
    rpc: "save_home_entry",
    args: {
      ...common,
      ...dates,
      p_address: null,
      p_city: null,
      p_country: null,
      p_latitude: null,
      p_longitude: null,
      p_move_in_reason: "",
      p_move_out_reason: "",
      p_place_id: null,
      p_place_name: "Harbor flat",
      p_place_notes: "",
      p_region: null,
    },
  },
  vehicle: {
    label: "Vehicle",
    path: "/vehicles",
    rpc: "save_vehicle_entry",
    args: {
      ...common,
      ...dates,
      p_color: "",
      p_make: "Test",
      p_model: "Car",
      p_model_year: null,
    },
  },
  first_time: {
    label: "First Time",
    path: "/first-times",
    rpc: "save_first_time_with_occurrence",
    args: { ...common, ...dates },
  },
} as const;
type RecordKind = keyof typeof records;

async function createRecord(
  client: SupabaseClient,
  kind: RecordKind,
  title: string,
  collectionNames: string[] = [],
) {
  const config = records[kind];
  const saved = await client.rpc(config.rpc, {
    ...config.args,
    p_collection_names: collectionNames,
    p_title: title,
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

/** Adds one photo through the focused editor, then reopens it at the photo revision. */
async function openWithSavedPhoto(
  page: Page,
  client: SupabaseClient,
  kind: RecordKind,
  entry: string,
) {
  const { label, path } = records[kind];
  await page.goto(`${path}/${entry}`);
  await page
    .getByRole("button", { name: `Edit ${label}`, exact: true })
    .click();
  const editor = page.getByRole("main");
  await editor.locator('input[type="file"]').setInputFiles({
    name: "kept.png",
    mimeType: "image/png",
    buffer: await photo(),
  });
  await editor
    .getByRole("button", { name: "Save changes", exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: `Edit ${label}`, exact: true }),
  ).toBeVisible();
  await expect.poll(() => currentPhotos(client, entry)).toBe(1);
  // Reload so the editor opens from the server's current photo revision.
  await page.reload();
  await page
    .getByRole("button", { name: `Edit ${label}`, exact: true })
    .click();
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

async function moveToTrash(page: Page, editor: Locator, title: string) {
  await editor
    .getByRole("button", { name: "Move to Trash", exact: true })
    .click();
  await page
    .getByRole("dialog", { name: `Move “${title}” to Trash?` })
    .getByRole("button", { name: "Move to Trash", exact: true })
    .click();
}

for (const kind of Object.keys(records) as RecordKind[]) {
  test(`${records[kind].label} moves to Trash after removing a photo in the same editor`, async ({
    page,
    account: { client },
  }) => {
    const uiErrors: string[] = [];
    page.on("pageerror", (error) => uiErrors.push(error.message));
    const title = `Photo revision ${kind}`;
    const entry = await createRecord(client, kind, title);
    const { editor, opened } = await openWithSavedPhoto(
      page,
      client,
      kind,
      entry,
    );

    await removePhoto(page, editor);
    await expect
      .poll(async () => (await entryRow(client, entry)).revision)
      .toBe(opened + 1);
    await moveToTrash(page, editor, title);

    await expect(page).toHaveURL(records[kind].path);
    await expect(page.getByText(/changed on another device/)).toHaveCount(0);
    expect((await entryRow(client, entry)).deleted_at).not.toBeNull();
    expect(uiErrors).toEqual([]);
  });
}

test("Goal achievement succeeds after removing a photo in the same editor", async ({
  page,
  account: { client },
}) => {
  const title = "Photo revision achievement";
  const entry = await createRecord(client, "goal", title, ["Bucket List"]);
  const { editor } = await openWithSavedPhoto(page, client, "goal", entry);

  await removePhoto(page, editor);
  const achieve = editor.getByRole("button", {
    name: "Mark achieved and create First Time",
    exact: true,
  });
  await achieve.click();

  await expect(
    page.getByText("Achievement saved, with a linked First Time."),
  ).toBeVisible();
  await expect(achieve).toHaveCount(0);
  await expect(editor.getByText(/changed or is no longer/)).toHaveCount(0);
  const achieved = await client
    .from("entries")
    .select("goals(status)")
    .eq("id", entry)
    .single();
  expect(achieved.data?.goals).toEqual([{ status: "achieved" }]);
  const links = await client
    .from("entry_links")
    .select("target_entry_id")
    .eq("source_entry_id", entry)
    .eq("relationship", "achievement");
  expect(links.data).toHaveLength(1);
});

test("Goal moves to Trash after a partial photo upload failure", async ({
  page,
  account: { client },
}) => {
  const title = "Photo revision partial upload";
  const entry = await createRecord(client, "goal", title);
  let failed = false;
  await page.route("**/storage/v1/object/entry-media/**", async (route) => {
    if (!failed && route.request().method() === "POST") {
      failed = true;
      await route.abort("failed");
    } else await route.continue();
  });
  await page.goto(`/goals/${entry}`);
  await page.getByRole("button", { name: "Edit Goal", exact: true }).click();
  const editor = page.getByRole("main");
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
  await moveToTrash(page, editor, title);

  await expect(page).toHaveURL("/goals");
  expect((await entryRow(client, entry)).deleted_at).not.toBeNull();
});

test("Goal Trash still refuses another device's writing after a photo removal", async ({
  page,
  account: { client },
}) => {
  const title = "Photo revision conflict";
  const entry = await createRecord(client, "goal", title);
  const { editor } = await openWithSavedPhoto(page, client, "goal", entry);

  await removePhoto(page, editor);
  expect(
    (
      await client
        .from("entries")
        .update({ body: "Other device writing" })
        .eq("id", entry)
    ).error,
  ).toBeNull();
  await moveToTrash(page, editor, title);

  await expect(
    editor.getByText(
      "This Goal changed on another device. Close it, refresh, and try again.",
    ),
  ).toBeVisible();
  expect((await entryRow(client, entry)).deleted_at).toBeNull();
});
