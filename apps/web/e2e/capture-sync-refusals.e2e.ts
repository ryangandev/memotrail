import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import {
  expect,
  test,
  type Browser,
  type BrowserContext,
  type Locator,
  type Page,
} from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import sharp from "sharp";
import { clickUnlessSynced } from "./helpers/capture-sync";
import { sql } from "./helpers/database";
import { cleanupMediaFixture } from "./helpers/media-fixture";

// A pending capture stops for good, with a reason, when MemoTrail can never
// accept it: Storage refuses its photo, its Entry is already in Trash, or its
// Entry was deleted forever. Only an upload that may still succeed waits.

const offlinePhotos =
  "Photos are saved on this device. MemoTrail will retry when you are online.";
const offlineEntry =
  "Saved on this device. MemoTrail will retry when you are online.";
const deletedForever =
  "This Entry was deleted forever, so MemoTrail will not create it again. Copy its text to keep it, then discard it.";
const trashedEntry =
  "This Entry is already in Trash, so it will not sync again. Restore it from Trash to keep it, then discard this copy.";
const trashedPhoto =
  "This Entry is in Trash, so its photos will not be attached. Discard to remove them from this device.";

// The first visit can compile the workspace and its Server Actions.
const firstCompile = { timeout: 90_000 };

type Account = {
  client: SupabaseClient;
  /** Opens another signed-in browser, like a second device. */
  otherDevice: () => Promise<Page>;
  owner: string;
};

for (const { body, label, message } of [
  {
    label: "too large",
    body: {
      statusCode: "413",
      error: "Payload too large",
      message: "The object exceeded the maximum allowed size",
      code: "EntityTooLarge",
    },
    message:
      "This Entry is in your Library, but one of its photos is too large for MemoTrail, so they will not sync. Discard to remove them from this device.",
  },
  {
    // Storage reports an expired session the same way, so the client checks
    // that this one is still valid before calling it a refusal.
    label: "denied for a signed-in person",
    body: {
      statusCode: "403",
      error: "Unauthorized",
      message: "new row violates row-level security policy",
      code: "AccessDenied",
    },
    message:
      "This Entry is in your Library, but MemoTrail cannot accept one of its photos, so they will not sync. Discard to remove them from this device.",
  },
]) {
  test(`a photo Storage refuses as ${label} is not accepted and never retried`, async ({
    browser,
    context,
    page,
  }) => {
    test.setTimeout(180_000);
    await withAccount(browser, context, async ({ client }) => {
      const composer = await openComposer(page);
      const uploads = countUploads(page);
      await page.route(uploadRoute, (route) =>
        route.request().method() === "POST"
          ? route.fulfill({ status: 400, json: body })
          : route.continue(),
      );

      await saveCapture(page, composer, `Refused photo ${label}`, true);
      const card = pendingCard(page, `Refused photo ${label}`);
      await expect(card).toContainText("Not accepted", firstCompile);
      await expect(card).toContainText(message);
      await expect(composer).not.toContainText(offlinePhotos);
      await expect(pendingIndicator(page)).toHaveText("1 not accepted");
      await expect(retryButton(page)).toHaveCount(0);

      // The Entry reached the Library; only its photo was refused, unregistered.
      const [entry] = await entries(client, `Refused photo ${label}`);
      expect(entry.deleted_at).toBeNull();
      expect(await attachmentCount(client, entry.id)).toBe(0);

      // A later capture still syncs, and the refused photo is never sent again.
      await page.unroute(uploadRoute);
      await saveCapture(page, composer, "A later capture");
      await expect
        .poll(async () => entries(client, "A later capture"))
        .toHaveLength(1);
      await page.reload();
      await expect(card).toContainText(message, firstCompile);
      await page.waitForLoadState("networkidle");
      expect(uploads()).toBe(1);

      await card.getByRole("button", { name: "Discard", exact: true }).click();
      const confirmation = page.getByRole("dialog", {
        name: "Discard this pending Entry?",
      });
      await expect(confirmation).toContainText(
        "Its text and photos will be removed from this device.",
      );
      await confirmation
        .getByRole("button", { name: "Discard", exact: true })
        .click();
      await expect(
        page.getByText("Pending Entry discarded.", { exact: true }),
      ).toBeVisible();
      await expect(pendingIndicator(page)).toHaveCount(0);
      expect(await entries(client, `Refused photo ${label}`)).toHaveLength(1);
    });
  });
}

test("a photo upload whose response was lost waits, then attaches the stored original", async ({
  browser,
  context,
  page,
}) => {
  test.setTimeout(180_000);
  await withAccount(browser, context, async ({ client }) => {
    const composer = await openComposer(page);
    const uploads: number[] = [];
    page.on("response", (response) => {
      if (isUpload(response.request().url(), response.request().method()))
        uploads.push(response.status());
    });
    // The original reaches Storage, but the browser never hears back.
    let lost = false;
    await page.route(uploadRoute, async (route) => {
      if (route.request().method() !== "POST" || lost) return route.continue();
      lost = true;
      await route.fetch();
      await route.abort("internetdisconnected");
    });

    await saveCapture(page, composer, "Photo with a lost upload", true);
    await expect(composer).toContainText(offlinePhotos, firstCompile);
    const card = pendingCard(page, "Photo with a lost upload");
    await expect(card).toContainText("On this device");
    const [entry] = await entries(client, "Photo with a lost upload");
    expect(await attachmentCount(client, entry.id)).toBe(0);

    // Storage reports the stored original as a duplicate, which still attaches.
    await clickUnlessSynced(retryButton(page));
    await expect(
      page.getByText("Saved to Library with 1 photo.", { exact: true }),
    ).toBeVisible({ timeout: 30_000 });
    await expect(card).toHaveCount(0);
    expect(uploads).toEqual([400]);
    expect(await attachmentCount(client, entry.id)).toBe(1);
    // The Dashboard finishes once the attached photo's preview has loaded.
    const preview = page.locator('main img[src*="/api/media/image"]').first();
    await expect
      .poll(() =>
        preview.evaluate(
          (img: HTMLImageElement) => img.complete && img.naturalWidth > 0,
        ),
      )
      .toBe(true);
  });
});

test("a pending capture whose Entry is already in Trash stops instead of retrying", async ({
  browser,
  context,
  page,
}) => {
  test.setTimeout(180_000);
  await withAccount(browser, context, async ({ client }) => {
    const composer = await openComposer(page);
    const uploads = countUploads(page);

    // The photo waits for Storage while the Entry is moved to Trash.
    await page.route(uploadRoute, (route) =>
      route.request().method() === "POST"
        ? route.abort("internetdisconnected")
        : route.continue(),
    );
    await saveCapture(page, composer, "Trashed while its photo waited", true);
    await expect(composer).toContainText(offlinePhotos, firstCompile);
    await moveToTrash(client, "Trashed while its photo waited");
    await page.unroute(uploadRoute);
    await clickUnlessSynced(retryButton(page));
    const photoCard = pendingCard(page, "Trashed while its photo waited");
    await expect(photoCard).toContainText(trashedPhoto, { timeout: 30_000 });
    await expect(photoCard).toContainText("Not accepted");
    // Retries while Storage was unreachable may have tried the upload again.
    const refusedUploads = uploads();

    // A capture without photos whose saved response was lost, then trashed.
    await loseSavedResponse(page, "Trashed before its retry");
    await saveCapture(page, composer, "Trashed before its retry");
    await expect(composer).toContainText(offlineEntry, firstCompile);
    await moveToTrash(client, "Trashed before its retry");
    await page.unroute("**/*");
    await clickUnlessSynced(retryButton(page));
    const textCard = pendingCard(page, "Trashed before its retry");
    await expect(textCard).toContainText(trashedEntry, { timeout: 30_000 });
    await expect(pendingIndicator(page)).toHaveText("2 not accepted");
    await expect(retryButton(page)).toHaveCount(0);

    // Neither comes back from Trash or is sent again, and later captures sync.
    await saveCapture(page, composer, "A capture after Trash");
    await expect
      .poll(async () => entries(client, "A capture after Trash"))
      .toHaveLength(1);
    await page.reload();
    await expect(textCard).toContainText(trashedEntry, firstCompile);
    await page.waitForLoadState("networkidle");
    expect(uploads()).toBe(refusedUploads);
    for (const body of [
      "Trashed while its photo waited",
      "Trashed before its retry",
    ]) {
      const [entry] = await entries(client, body);
      expect(entry.deleted_at).not.toBeNull();
      expect(await attachmentCount(client, entry.id)).toBe(0);
    }
  });
});

test("Delete forever on another device never brings back a pending capture", async ({
  browser,
  context,
  page,
}) => {
  test.setTimeout(240_000);
  await withAccount(browser, context, async ({ client, otherDevice }) => {
    await context.grantPermissions(["clipboard-read", "clipboard-write"]);
    const composer = await openComposer(page);
    const text = "Deleted forever while pending";

    // The Entry reaches MemoTrail, but this device never hears back.
    await loseSavedResponse(page, text);
    await saveCapture(page, composer, text);
    await expect(composer).toContainText(offlineEntry, firstCompile);
    await moveToTrash(client, text);

    const trash = await otherDevice();
    await trash.goto("/trash");
    const dialog = await confirmDeletion(trash, text);
    await dialog
      .getByRole("button", { name: "Delete forever", exact: true })
      .click();
    await expect(
      trash.getByText("Item permanently deleted.", { exact: true }),
    ).toBeVisible(firstCompile);
    expect(await entries(client, text)).toHaveLength(0);

    await page.unroute("**/*");
    await clickUnlessSynced(retryButton(page));
    const card = pendingCard(page, text);
    await expect(card).toContainText(deletedForever, { timeout: 30_000 });
    await expect(card).toContainText("Not accepted");
    await expect(retryButton(page)).toHaveCount(0);
    expect(await entries(client, text)).toHaveLength(0);

    // Its text is still the person's to keep.
    await card.getByRole("button", { name: "Copy text", exact: true }).click();
    await expect(page.getByText("Text copied.", { exact: true })).toBeVisible();
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(
      text,
    );

    // It stays refused after a reload, and a later capture still syncs.
    await page.reload();
    await expect(card).toContainText(deletedForever, firstCompile);
    await saveCapture(page, composer, "A capture after Delete forever");
    await expect
      .poll(async () => entries(client, "A capture after Delete forever"))
      .toHaveLength(1);
    expect(await entries(client, text)).toHaveLength(0);
  });
});

test("a photo that arrives after Delete forever is refused and its upload removed", async ({
  browser,
  context,
  page,
}) => {
  test.setTimeout(180_000);
  await withAccount(browser, context, async ({ client, owner }) => {
    const composer = await openComposer(page);
    const text = "Deleted forever during its upload";
    let entryId = "";

    // The original is stored just as the Entry is deleted forever elsewhere.
    await page.route(uploadRoute, async (route) => {
      if (route.request().method() !== "POST") return route.continue();
      const response = await route.fetch();
      entryId = (await moveToTrash(client, text)).id;
      await deleteForever(client, entryId);
      await route.fulfill({ response });
    });

    await saveCapture(page, composer, text, true);
    const card = pendingCard(page, text);
    await expect(card).toContainText(deletedForever, firstCompile);
    await expect(card).toContainText("Not accepted");
    expect(entryId).not.toBe("");
    expect(await entries(client, text)).toHaveLength(0);
    // The unregistered original does not outlive its Entry.
    await expect.poll(() => entryObjects(owner, entryId)).toBe(0);
  });
});

const uploadRoute = "**/storage/v1/object/entry-media/**";

function isUpload(url: string, method: string) {
  return method === "POST" && url.includes("/storage/v1/object/entry-media/");
}

function countUploads(page: Page) {
  let count = 0;
  page.on("request", (request) => {
    if (isUpload(request.url(), request.method())) count += 1;
  });
  return () => count;
}

/**
 * Lets a capture's save reach MemoTrail and drops the response, then keeps
 * this device from reaching MemoTrail until the route is removed, so the
 * capture keeps waiting however often it is retried.
 */
async function loseSavedResponse(page: Page, text: string) {
  let lost = false;
  await page.route("**/*", async (route) => {
    const request = route.request();
    if (request.method() === "POST" && request.headers()["next-action"]) {
      if (!lost && (request.postData() ?? "").includes(text)) {
        lost = true;
        await route.fetch();
      }
      if (lost) return route.abort("internetdisconnected");
    }
    await route.continue();
  });
}

async function openComposer(page: Page) {
  await page.goto("/");
  const composer = page
    .locator("main")
    .getByRole("form", { name: "Quick capture", exact: true });
  await expect(
    composer.getByRole("textbox", { name: "Entry text", exact: true }),
  ).toBeVisible(firstCompile);
  await expect(
    composer.getByRole("button", { name: "Add photos", exact: true }),
  ).toBeEnabled();
  await page.waitForLoadState("networkidle");
  return composer;
}

async function saveCapture(
  page: Page,
  composer: Locator,
  text: string,
  withPhoto = false,
) {
  if (withPhoto)
    await composer.locator('input[type="file"]').setInputFiles({
      name: "trail.png",
      mimeType: "image/png",
      buffer: await sharp({
        create: { width: 32, height: 24, channels: 3, background: "#426e83" },
      })
        .png()
        .toBuffer(),
    });
  const save = composer.getByRole("button", {
    name: "Save",
    exact: true,
  });
  await expect(save).toBeEnabled({ timeout: 60_000 });
  await composer
    .getByRole("textbox", { name: "Entry text", exact: true })
    .click();
  await page.keyboard.insertText(text);
  await save.click();
}

function pendingCard(page: Page, text: string) {
  return page
    .locator("main")
    .getByRole("region", { name: "Pending sync" })
    .getByRole("article")
    .filter({ hasText: text });
}

function retryButton(page: Page) {
  return page
    .locator("main")
    .getByRole("region", { name: "Pending sync" })
    .getByRole("button", { name: "Retry now", exact: true });
}

function pendingIndicator(page: Page) {
  return page
    .locator("[data-ui-sync-status]")
    .filter({ visible: true })
    .getByText(/^\d+ (pending|not accepted)( · \d+ not accepted)?$/);
}

/**
 * Opens the Delete forever confirmation for the Trash row showing `text`,
 * retrying a click made before hydration. The confirmation names the row by
 * its heading, which is the date for an untitled Entry.
 */
async function confirmDeletion(page: Page, text: string) {
  const dialog = page.getByRole("dialog");
  const row = page.getByRole("article").filter({ hasText: text });
  // Read before opening: the modal confirmation hides the rest of the page.
  const heading = await row.getByRole("heading").first().innerText();
  await expect(async () => {
    if (!(await dialog.isVisible())) {
      await row
        .getByRole("button", { name: "Delete forever", exact: true })
        .click();
    }
    await expect(dialog).toBeVisible({ timeout: 2_000 });
  }).toPass(firstCompile);
  await expect(dialog).toContainText(`Delete “${heading}” forever?`);
  return dialog;
}

async function entries(client: SupabaseClient, body: string) {
  const { data, error } = await client
    .from("entries")
    .select("id,revision,deleted_at")
    .eq("body", body);
  expect(error).toBeNull();
  return (data ?? []) as {
    deleted_at: string | null;
    id: string;
    revision: number;
  }[];
}

async function attachmentCount(client: SupabaseClient, entryId: string) {
  const { data, error } = await client
    .from("attachments")
    .select("id")
    .eq("entry_id", entryId);
  expect(error).toBeNull();
  return data?.length ?? 0;
}

/** Moves the Entry to Trash the way the Item page does. */
async function moveToTrash(client: SupabaseClient, body: string) {
  await expect.poll(async () => entries(client, body)).toHaveLength(1);
  const [entry] = await entries(client, body);
  const { error } = await client
    .from("entries")
    .update({ deleted_at: new Date().toISOString() })
    .eq("id", entry.id);
  expect(error).toBeNull();
  return entry;
}

async function deleteForever(client: SupabaseClient, entryId: string) {
  const { data: trashed, error } = await client
    .from("entries")
    .select("revision,deleted_at")
    .eq("id", entryId)
    .single();
  expect(error).toBeNull();
  const deleted = await client.rpc("delete_trash_item_forever", {
    p_item_kind: "entry",
    p_item_id: entryId,
    p_expected_revision: trashed!.revision,
    p_expected_deleted_at: trashed!.deleted_at,
  });
  expect(deleted.error).toBeNull();
  expect(deleted.data).toHaveLength(1);
}

/** Counts every Storage object of one Entry. */
function entryObjects(owner: string, entryId: string) {
  return Number(
    sql(
      `select count(*) from storage.objects where bucket_id='entry-media' and starts_with(name,'${owner}/${entryId}/')`,
    ).trim(),
  );
}

async function withAccount(
  browser: Browser,
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
  const email = `media-capture-sync-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  expect(created.error).toBeNull();
  const owner = created.data.user!.id;
  const devices: BrowserContext[] = [];
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
    expect(link.error).toBeNull();
    expect(
      (
        await client.auth.verifyOtp({
          type: "magiclink",
          token_hash: link.data.properties!.hashed_token,
        })
      ).error,
    ).toBeNull();
    const sessionCookies = cookies.map((cookie) => ({
      ...cookie,
      domain: "127.0.0.1",
      path: "/",
      sameSite: "Lax" as const,
    }));
    await context.addCookies(sessionCookies);
    await run({
      client,
      owner,
      async otherDevice() {
        const device = await browser.newContext({
          baseURL: test.info().project.use.baseURL,
        });
        devices.push(device);
        await device.addCookies(sessionCookies);
        return device.newPage();
      },
    });
  } finally {
    for (const device of devices) await device.close();
    await cleanupMediaFixture(admin, owner, env.API_URL);
  }
}
