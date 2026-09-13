import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import sharp from "sharp";
import { cleanupMediaFixture } from "./helpers/media-fixture";

test("Current Entry photos are browsable without changing history", async ({
  page,
  context,
}) => {
  test.setTimeout(120_000);
  const env = JSON.parse(
    execFileSync("supabase", ["status", "-o", "json"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }),
  );
  expect(env.API_URL).toBe("http://127.0.0.1:54321");
  const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY);
  const email = `media-gallery-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  expect(created.error).toBeNull();
  const owner = created.data.user!.id,
    entry = randomUUID();
  const attachmentIDs: string[] = [];
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
    const signed = await client.auth.verifyOtp({
      type: "magiclink",
      token_hash: link.data.properties!.hashed_token,
    });
    await context.addCookies(
      cookies.map((c) => ({
        ...c,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax",
      })),
    );
    expect(
      (
        await client.from("entries").insert({
          id: entry,
          owner_id: owner,
          title: "Gallery acceptance",
          body: "Preserve this writing",
          inbox_status: "organized",
        })
      ).error,
    ).toBeNull();
    for (const [index, width, height] of [
      [1, 240, 400],
      [2, 400, 240],
    ]) {
      const attachment = randomUUID(),
        path = `${owner}/${entry}/${attachment}.jpg`;
      attachmentIDs.push(attachment);
      const bytes = await sharp({
        create: {
          width,
          height,
          channels: 3,
          background: index === 1 ? "#316652" : "#bb7645",
        },
      })
        .jpeg()
        .toBuffer();
      expect(
        (
          await client.storage
            .from("entry-media")
            .upload(path, bytes, { contentType: "image/jpeg" })
        ).error,
      ).toBeNull();
      expect(
        (
          await client.rpc("register_entry_attachment", {
            p_entry_id: entry,
            p_attachment_id: attachment,
            p_object_path: path,
            p_original_filename: `Photo ${index}.jpg`,
            p_mime_type: "image/jpeg",
            p_byte_size: bytes.length,
            p_pixel_width: width,
            p_pixel_height: height,
          })
        ).error,
      ).toBeNull();
    }
    const before = (
      await client.from("entries").select("*").eq("id", entry).single()
    ).data;
    const native = await page.request.post(
      `/api/media/photos?entryId=${entry}`,
      {
        headers: {
          Authorization: `Bearer ${signed.data.session!.access_token}`,
        },
      },
    );
    expect(native.status()).toBe(200);
    expect((await native.json()).photos).toHaveLength(2);
    await page.goto(`/history?entry=${entry}`);
    const gallery = page.getByRole("region", {
      name: "Current photos",
      exact: true,
    });
    await expect(gallery).toBeVisible();
    await gallery
      .getByRole("button", { name: "Show photos", exact: true })
      .click();
    await expect(
      gallery.getByRole("button", { name: "Open Photo 1.jpg", exact: true }),
    ).toBeVisible();
    await gallery
      .getByRole("button", { name: "Open Photo 1.jpg", exact: true })
      .click();
    const viewer = page.getByRole("dialog", { name: "Photo viewer" });
    await expect(viewer).toBeVisible();
    await expect(viewer.getByRole("img")).toHaveCSS("object-fit", "contain");
    await expect
      .poll(() =>
        viewer
          .getByRole("img")
          .evaluate((img: HTMLImageElement) => img.naturalWidth),
      )
      .toBeGreaterThan(0);
    await expect(viewer).toContainText("1 of 2");
    await expect(
      viewer.getByRole("button", { name: "Previous photo", exact: true }),
    ).toBeDisabled();
    await page.screenshot({
      path: "/private/tmp/memotrail-gallery-desktop-light.png",
    });
    await viewer
      .getByRole("button", { name: "Next photo", exact: true })
      .click();
    await expect(viewer.getByRole("img")).toHaveAttribute("alt", "Photo 2.jpg");
    await expect(
      viewer.getByRole("button", { name: "Next photo", exact: true }),
    ).toBeDisabled();
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.screenshot({
      path: "/private/tmp/memotrail-gallery-mobile-dark.png",
    });
    await page.keyboard.press("Escape");
    await expect(viewer).toHaveCount(0);
    await expect(
      gallery.getByRole("button", { name: "Open Photo 1.jpg", exact: true }),
    ).toBeFocused();
    await page.route("**/api/media/photos?*", (route) =>
      route.fulfill({ status: 503, json: { error: "Unavailable" } }),
    );
    await gallery
      .getByRole("button", { name: "Refresh photos", exact: true })
      .click();
    await expect(gallery.getByRole("alert")).toContainText(
      "Could not load photos",
    );
    await expect(
      gallery.getByRole("button", { name: /^Open Photo/ }),
    ).toHaveCount(0);
    await page.unroute("**/api/media/photos?*");
    await gallery
      .getByRole("button", { name: "Show photos", exact: true })
      .click();
    await expect(
      gallery.getByRole("button", { name: /^Open Photo/ }),
    ).toHaveCount(2);
    expect(
      (await client.from("entries").select("*").eq("id", entry).single()).data,
    ).toEqual(before);
    await page.route("**/api/media/image?*", (route) =>
      route.fulfill({ status: 404 }),
    );
    await gallery
      .getByRole("button", { name: "Open Photo 1.jpg", exact: true })
      .click();
    await expect(viewer.getByRole("status")).toContainText("Photo unavailable");
    await viewer.getByRole("button", { name: "Close", exact: true }).click();
    await page.unroute("**/api/media/image?*");
    expect(
      (
        await client.rpc("trash_entry_attachment", {
          p_attachment_id: attachmentIDs[0],
        })
      ).error,
    ).toBeNull();
    await gallery
      .getByRole("button", { name: "Refresh photos", exact: true })
      .click();
    await expect(
      gallery.getByRole("button", { name: /^Open Photo/ }),
    ).toHaveCount(1);
    await expect(
      gallery.getByRole("button", { name: "Open Photo 2.jpg", exact: true }),
    ).toBeVisible();
    const trashed = await client
      .from("attachments")
      .select("deleted_at")
      .eq("id", attachmentIDs[0])
      .single();
    expect(trashed.error).toBeNull();
    expect(
      (
        await client.rpc("restore_trash_item", {
          p_item_id: attachmentIDs[0],
          p_item_kind: "attachment",
          p_expected_revision: null,
          p_expected_deleted_at: trashed.data!.deleted_at,
        })
      ).error,
    ).toBeNull();
    await gallery
      .getByRole("button", { name: "Refresh photos", exact: true })
      .click();
    await expect(
      gallery.getByRole("button", { name: /^Open Photo/ }),
    ).toHaveCount(2);
  } finally {
    await cleanupMediaFixture(admin, owner, env.API_URL);
  }
});
