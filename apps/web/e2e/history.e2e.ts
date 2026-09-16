import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
test("History restores and re-restores writing, relationships, and private photo membership with conflict protection", async ({
  page,
  context,
}) => {
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
  const email = `history-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  if (!created.data.user) throw new Error("Local history fixture unavailable.");
  const ownerID = created.data.user.id,
    entryID = randomUUID(),
    photoID = randomUUID(),
    collectionID = randomUUID();
  const path = `${ownerID}/${entryID}/${photoID}.png`;
  const bytes = Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=",
    "base64",
  );
  try {
    const cookies: { name: string; value: string }[] = [];
    const client = createServerClient(env.API_URL, env.ANON_KEY, {
      cookies: {
        getAll: () => cookies,
        setAll: (values) => {
          cookies.push(
            ...values.map((v) => ({ name: v.name, value: v.value })),
          );
        },
      },
    });
    const link = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    if (!link.data.properties) throw new Error("Local sign-in unavailable.");
    expect(
      (
        await client.auth.verifyOtp({
          type: "magiclink",
          token_hash: link.data.properties.hashed_token,
        })
      ).error,
    ).toBeNull();
    await context.addCookies(
      cookies.map((c) => ({
        ...c,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax" as const,
        httpOnly: false,
      })),
    );
    expect(
      (
        await client.from("entries").insert({
          id: entryID,
          owner_id: ownerID,
          title: "Original chapter",
          body: "The original words I want to keep.",
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("collections").insert({
          id: collectionID,
          owner_id: ownerID,
          name: "Original collection",
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("entry_collections").insert({
          entry_id: entryID,
          collection_id: collectionID,
          owner_id: ownerID,
        })
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
          p_entry_id: entryID,
          p_attachment_id: photoID,
          p_object_path: path,
          p_original_filename: "memory.png",
          p_mime_type: "image/png",
          p_byte_size: bytes.length,
          p_pixel_width: 1,
          p_pixel_height: 1,
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.rpc("review_wiki_item_with_photo_place", {
          p_entry_id: entryID,
          p_expected_revision: 2,
          p_title: "Revised chapter",
          p_body: "The newer words before restoration.",
          p_item_kind: "writing",
          p_item_subtype: "note",
          p_occurred_start: "2024-01-01T12:00:00Z",
          p_occurred_timezone: "UTC",
          p_collection_names: [],
          p_tag_names: [],
          p_mark_done: false,
          p_occurred_end: null,
          p_occurred_label: null,
          p_date_precision: "day",
          p_photo_place: null,
        })
      ).error,
    ).toBeNull();
    const errors: string[] = [];
    page.on("pageerror", (e) => errors.push(e.message));
    await page.goto("/history");
    await page.getByRole("link", { name: /Revised chapter/ }).click();
    const earlier = page.getByRole("region", { name: "Earlier version" }),
      current = page.getByRole("region", { name: "Current version" });
    await expect(earlier).toContainText("The original words I want to keep.");
    await expect(earlier).toContainText("Original collection");
    await expect(earlier).toContainText("memory.png");
    await expect(current).toContainText("The newer words before restoration.");
    await page.screenshot({
      path: "/private/tmp/memotrail-history-desktop.png",
      fullPage: true,
      caret: "initial",
    });
    page.once("dialog", (d) => d.accept());
    await page
      .getByRole("button", { name: "Restore selected version" })
      .click();
    await expect(current).toContainText("Current · version 4");
    await expect(current).toContainText("The original words I want to keep.");
    const restored = await client
      .from("entry_collections")
      .select("collection_id")
      .eq("entry_id", entryID);
    expect(restored.data?.[0]?.collection_id).toBe(collectionID);
    page.once("dialog", (d) => d.accept());
    await page
      .getByRole("button", { name: "Restore selected version" })
      .click();
    await expect(current).toContainText("Current · version 5");
    await expect(current).toContainText("The newer words before restoration.");
    expect(
      (
        await client
          .from("entries")
          .update({ body: "Another device updated this Entry." })
          .eq("id", entryID)
      ).error,
    ).toBeNull();
    page.once("dialog", (d) => d.accept());
    await page
      .getByRole("button", { name: "Restore selected version" })
      .click();
    await expect(
      page.getByRole("alert").filter({ hasText: "changed on another device" }),
    ).toContainText("changed on another device");
    const fresh = await client
      .from("entries")
      .select("revision,body")
      .eq("id", entryID)
      .single();
    expect(fresh.data?.revision).toBe(6);
    expect(fresh.data?.body).toBe("Another device updated this Entry.");
    const downloaded = await client.storage.from("entry-media").download(path);
    expect(downloaded.error).toBeNull();
    expect(Buffer.from(await downloaded.data!.arrayBuffer())).toEqual(bytes);
    await page.reload();
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await expect(current).toContainText("Current · version 6");
    await page.screenshot({
      path: "/private/tmp/memotrail-history-mobile.png",
      fullPage: true,
      caret: "initial",
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);
    expect(errors).toEqual([]);
  } finally {
    const removed = await admin.storage.from("entry-media").remove([path]);
    const deleted = await admin.auth.admin.deleteUser(ownerID);
    if (removed.error || deleted.error)
      throw new Error("Could not clean up isolated history fixtures.");
  }
});
