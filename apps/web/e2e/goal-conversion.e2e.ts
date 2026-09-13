import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import sharp from "sharp";
import { cleanupMediaFixture } from "./helpers/media-fixture";
test("An Idea converts in place, preserves its original content, and can be restored", async ({
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
  const email = `goal-conversion-${randomUUID()}@memotrail.local`;
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
  const bytes = await sharp({
    create: { width: 1, height: 1, channels: 3, background: "#316652" },
  })
    .png()
    .toBuffer();
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
          name: "Ideas",
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
        await client
          .from("entries")
          .update({
            occurred_start: "2017-07-08T12:00:00.123456Z",
            occurred_end: "2017-07-15T12:00:00Z",
            date_precision: "range",
            occurred_timezone: "UTC",
          })
          .eq("id", entryID)
      ).error,
    ).toBeNull();
    const before = (
      await client.rpc("entry_history", {
        p_entry_id: entryID,
        p_limit: 20,
        p_offset: 0,
      })
    ).data.current;
    const errors: string[] = [];
    page.on("pageerror", (e) => errors.push(e.message));
    await page.goto("/history?entry=" + entryID);
    await page
      .getByRole("button", { name: "Convert to Goal", exact: true })
      .click();
    const form = page.getByRole("form", { name: "Convert Entry to Goal" });
    await expect(form.getByLabel("Horizon")).toHaveValue("someday");
    await expect(
      form.getByRole("combobox", { name: "Status", exact: true }),
    ).toHaveValue("considering");
    await form.getByRole("button", { name: "Cancel", exact: true }).click();
    expect(
      (
        await client
          .from("entries")
          .select("entry_type")
          .eq("id", entryID)
          .single()
      ).data?.entry_type,
    ).toBe("standard");
    await page
      .getByRole("button", { name: "Convert to Goal", exact: true })
      .click();
    await form.getByLabel("Horizon").selectOption("long_term");
    await form
      .getByRole("combobox", { name: "Status", exact: true })
      .selectOption("active");
    await form.getByLabel("Target date (optional)").fill("2027-12-31");
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.screenshot({
      path: "/private/tmp/memotrail-goal-conversion-desktop.png",
    });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.screenshot({
      path: "/private/tmp/memotrail-goal-conversion-mobile.png",
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await form
      .getByRole("button", { name: "Convert this Entry", exact: true })
      .click();
    await expect(
      page.getByRole("link", { name: "Open Goal", exact: true }),
    ).toBeVisible();
    const after = (
      await client.rpc("entry_history", {
        p_entry_id: entryID,
        p_limit: 20,
        p_offset: 0,
      })
    ).data.current;
    for (const key of [
      "id",
      "body",
      "inbox_status",
      "created_at",
      "occurred_start",
      "occurred_end",
      "date_precision",
      "occurred_timezone",
      "collections",
      "tags",
      "people",
      "places",
      "links",
      "attachments",
      "metadata",
    ])
      expect(after[key], key).toEqual(before[key]);
    expect(after.goal.horizon).toBe("long_term");
    expect(after.goal.target_date).toBe("2027-12-31");
    const retry = await client.rpc("convert_entry_to_goal", {
      p_entry_id: entryID,
      p_expected_revision: before.revision,
      p_title: before.title,
      p_horizon: "long_term",
      p_status: "active",
      p_target_date: "2027-12-31",
    });
    expect(retry.error).toBeNull();
    expect(retry.data).toBe(after.revision);
    await page.getByRole("link", { name: "Open Goal", exact: true }).click();
    await page
      .getByRole("dialog")
      .getByRole("button", { name: "Save changes", exact: true })
      .click();
    await expect(page.getByRole("dialog")).not.toBeVisible();
    const later = (
      await client
        .from("entries")
        .select("occurred_start,occurred_end")
        .eq("id", entryID)
        .single()
    ).data!;
    expect(later.occurred_start).toBe(before.occurred_start);
    expect(later.occurred_end).toBe(before.occurred_end);
    await page.goto("/history?entry=" + entryID);
    await page
      .getByRole("combobox", { name: "Earlier version", exact: true })
      .selectOption(String(before.revision));
    page.once("dialog", (d) => d.accept());
    await page
      .getByRole("button", { name: "Restore selected version" })
      .click();
    await expect(
      page.getByRole("button", { name: "Convert to Goal", exact: true }),
    ).toBeVisible();
    expect(
      (await client.from("goals").select("entry_id").eq("entry_id", entryID))
        .data,
    ).toHaveLength(0);
    const downloaded = await client.storage.from("entry-media").download(path);
    expect(Buffer.from(await downloaded.data!.arrayBuffer())).toEqual(bytes);
    const restored = (
      await client.from("entries").select("revision").eq("id", entryID).single()
    ).data!.revision;
    const requests = await Promise.all(
      [0, 1].map(() =>
        client.rpc("convert_entry_to_goal", {
          p_entry_id: entryID,
          p_expected_revision: restored,
          p_title: before.title,
          p_horizon: "someday",
          p_status: "considering",
          p_target_date: null,
        }),
      ),
    );
    for (const request of requests) {
      expect(request.error).toBeNull();
      expect(request.data).toBe(restored + 1);
    }
    expect(
      (await client.from("goals").select("entry_id").eq("entry_id", entryID))
        .data,
    ).toHaveLength(1);
    expect(errors).toEqual([]);
  } finally {
    await cleanupMediaFixture(admin, ownerID, env.API_URL);
  }
});
