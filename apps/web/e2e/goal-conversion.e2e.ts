import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import sharp from "sharp";
import { cleanupMediaFixture } from "./helpers/media-fixture";
test("An Idea creates a linked Goal without changing the source", async ({
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
  const email = `goal-extraction-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  if (!created.data.user) throw new Error("Local history fixture unavailable.");
  const ownerID = created.data.user.id,
    entryID = randomUUID(),
    photoID = randomUUID(),
    tagID = randomUUID();
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
          item_kind: "entry",
          item_subtype: "entry",
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("tags").insert({
          id: tagID,
          owner_id: ownerID,
          name: "Ideas",
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("entry_tags").insert({
          entry_id: entryID,
          tag_id: tagID,
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
      .getByRole("button", { name: "Add to Want to Do", exact: true })
      .click();
    const form = page.getByRole("form", { name: "Add to Want to Do" });
    await expect(form.getByRole("combobox")).toHaveCount(0);
    await form.getByRole("button", { name: "Cancel", exact: true }).click();
    expect(
      (
        await client
          .from("entries")
          .select("item_kind,item_subtype")
          .eq("id", entryID)
          .single()
      ).data,
    ).toEqual({ item_kind: "entry", item_subtype: "entry" });
    await page
      .getByRole("button", { name: "Add to Want to Do", exact: true })
      .click();
    await form.getByLabel("Target date", { exact: true }).fill("2027-12-31");
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-goal-extraction-desktop.png",
    });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-goal-extraction-mobile.png",
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await form
      .getByRole("button", { name: "Add to Want to Do", exact: true })
      .click();
    await expect(page).toHaveURL(/\/goals\/[0-9a-f-]+$/);
    await expect(
      page.getByRole("button", { name: "Edit Want to Do" }),
    ).toBeVisible();
    const derivedLinks = await client
      .from("entry_links")
      .select("target_entry_id")
      .eq("source_entry_id", entryID)
      .eq("relationship", "derived")
      .single();
    expect(derivedLinks.error).toBeNull();
    const goalID = derivedLinks.data!.target_entry_id;
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
      "created_at",
      "occurred_start",
      "occurred_end",
      "date_precision",
      "occurred_timezone",
      "tags",
      "places",
      "attachments",
      "metadata",
      "revision",
      "item_kind",
      "item_subtype",
    ])
      expect(after[key], key).toEqual(before[key]);
    expect(after.links).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          relationship: "derived",
          target_entry_id: goalID,
        }),
      ]),
    );
    const goal = (
      await client.rpc("entry_history", {
        p_entry_id: goalID,
        p_limit: 20,
        p_offset: 0,
      })
    ).data.current;
    expect(goal.id).toBe(goalID);
    expect(goal.item_kind).toBe("goal");
    expect(goal.body).toBe(before.body);
    expect(goal.goal.status).toBe("active");
    expect(goal.goal).not.toHaveProperty("horizon");
    expect(goal.goal.target_date).toBe("2027-12-31");
    const retry = await client.rpc("extract_goal_from_item", {
      p_goal_id: goalID,
      p_status: "active",
      p_target_date: "2027-12-31",
      p_title: before.title,
      p_source_entry_id: entryID,
      p_source_revision: before.revision,
    });
    expect(retry.error).toBeNull();
    expect(retry.data).toHaveLength(1);
    expect(retry.data[0].goal_entry_id).toBe(goalID);
    await page.getByRole("button", { name: "Edit Want to Do" }).click();
    await page
      .getByRole("main")
      .getByRole("button", { name: "Save changes", exact: true })
      .click();
    await expect(
      page.getByRole("button", { name: "Edit Want to Do" }),
    ).toBeVisible();
    const later = (
      await client
        .from("entries")
        .select("occurred_start,occurred_end")
        .eq("id", entryID)
        .single()
    ).data!;
    expect(later.occurred_start).toBe(before.occurred_start);
    expect(later.occurred_end).toBe(before.occurred_end);
    await page.goto("/history?entry=" + goalID);
    await expect(
      page.getByRole("link", { name: "Open source item", exact: true }),
    ).toBeVisible();
    await page.goto("/history?entry=" + entryID);
    await expect(
      page.getByRole("button", { name: "Add to Want to Do", exact: true }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: "Open extracted item", exact: true }),
    ).toBeVisible();
    const downloaded = await client.storage.from("entry-media").download(path);
    expect(Buffer.from(await downloaded.data!.arrayBuffer())).toEqual(bytes);
    expect(
      (await client.from("goals").select("entry_id").eq("entry_id", goalID))
        .data,
    ).toHaveLength(1);
    expect(errors).toEqual([]);
  } finally {
    await cleanupMediaFixture(admin, ownerID, env.API_URL);
  }
});
