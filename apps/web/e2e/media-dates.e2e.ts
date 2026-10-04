import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import {
  fillOccurrenceStart,
  occurrenceStartField,
} from "./helpers/occurrence";
import sharp from "sharp";
import { cleanupMediaFixture } from "./helpers/media-fixture";

test("Camera dates are private, read-only suggestions until an explicit Entry save", async ({
  baseURL,
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
  const email = `media-dates-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  const owner = created.data.user!.id,
    entry = randomUUID(),
    attachment = randomUUID();
  const path = `${owner}/${entry}/${attachment}.jpg`;
  const origin = { Origin: baseURL! };
  let otherOwner: string | undefined;
  try {
    expect(
      (
        await page.request.post(
          `/api/media/metadata?attachmentId=${attachment}`,
          { headers: origin },
        )
      ).status(),
    ).toBe(401);
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
        httpOnly: false,
      })),
    );
    const bearer = {
      Authorization: `Bearer ${signed.data.session!.access_token}`,
    };
    expect(
      (
        await client.from("entries").insert({
          id: entry,
          owner_id: owner,
          title: "Camera date review",
          body: "Original writing",
          date_precision: "range",
          occurred_start: "2020-01-01T20:00:00Z",
          occurred_end: "2020-01-03T20:00:00Z",
          occurred_timezone: "America/Los_Angeles",
        })
      ).error,
    ).toBeNull();
    const bytes = await sharp({
      create: { width: 400, height: 240, channels: 3, background: "#316652" },
    })
      .withExif({
        IFD0: { Artist: "Private artist not returned" },
        IFD2: {
          DateTimeOriginal: "2017:07:08 12:34:56",
          OffsetTimeOriginal: "-04:00",
        },
        IFD3: {
          GPSLatitudeRef: "N",
          GPSLatitude: "39/1 57/1 0/1",
          GPSLongitudeRef: "W",
          GPSLongitude: "75/1 10/1 0/1",
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
          p_original_filename: "Synthetic camera photo.jpg",
          p_mime_type: "image/jpeg",
          p_byte_size: bytes.length,
          p_pixel_width: 400,
          p_pixel_height: 240,
        })
      ).error,
    ).toBeNull();
    const snapshot = async () =>
      (await client.from("entries").select("*").eq("id", entry).single()).data!;
    const before = await snapshot();
    const endpoint = `/api/media/metadata?attachmentId=${attachment}`;
    expect(
      (
        await page.request.post(endpoint, {
          headers: { Origin: "https://foreign.example" },
        })
      ).status(),
    ).toBe(403);
    expect(
      (
        await page.request.post(
          `/api/media/metadata?attachmentId=${"-".repeat(36)}`,
          { headers: bearer },
        )
      ).status(),
    ).toBe(400);
    expect(
      (
        await page.request.post(
          `/api/media/metadata?attachmentId=${randomUUID()}`,
          { headers: bearer },
        )
      ).status(),
    ).toBe(404);
    const native = await page.request.post(endpoint, { headers: bearer });
    expect(native.status()).toBe(200);
    expect(native.headers()["cache-control"]).toBe("private, no-store");
    const metadata = await native.json();
    expect(metadata).toMatchObject({
      attachmentId: attachment,
      calendarDate: "2017-07-08",
      offset: "-04:00",
      latitude: 39.95,
    });
    expect(JSON.stringify(metadata)).not.toContain("Private artist");
    expect(
      await (await page.request.post(endpoint, { headers: origin })).json(),
    ).toEqual(metadata);
    const photos = await page.request.post(
      `/api/media/photos?entryId=${entry}`,
      { headers: bearer },
    );
    expect((await photos.json()).photos[0].id).toBe(attachment);
    const otherEmail = `media-dates-${randomUUID()}@memotrail.local`;
    const otherUser = await admin.auth.admin.createUser({
      email: otherEmail,
      email_confirm: true,
    });
    otherOwner = otherUser.data.user!.id;
    const otherLink = await admin.auth.admin.generateLink({
      type: "magiclink",
      email: otherEmail,
    });
    const otherClient = createClient(env.API_URL, env.ANON_KEY, {
      auth: { persistSession: false },
    });
    const otherSession = await otherClient.auth.verifyOtp({
      type: "magiclink",
      token_hash: otherLink.data.properties!.hashed_token,
    });
    const otherHeaders = {
      Authorization: `Bearer ${otherSession.data.session!.access_token}`,
    };
    expect(
      (await page.request.post(endpoint, { headers: otherHeaders })).status(),
    ).toBe(404);
    expect(
      (
        await page.request.post(`/api/media/photos?entryId=${entry}`, {
          headers: otherHeaders,
        })
      ).status(),
    ).toBe(404);
    expect(await snapshot()).toEqual(before);
    await page.goto(`/history?entry=${entry}`);
    await page.getByRole("button", { name: "Edit Entry", exact: true }).click();
    const dialog = page.getByRole("dialog");
    await dialog
      .getByRole("button", { name: "Show photos", exact: true })
      .click();
    await dialog
      .getByRole("button", { name: "Read camera date", exact: true })
      .click();
    await expect(
      dialog.getByText("Camera time:", { exact: false }),
    ).toContainText("2017-07-08 12:34:56 (UTC-04:00)");
    await expect(dialog.getByText("39.950000, -75.166667")).toHaveCount(0);
    await dialog
      .getByRole("button", {
        name: "Use calendar date 2017-07-08",
        exact: true,
      })
      .click();
    await expect(dialog.getByLabel("Date type")).toHaveValue("day");
    await expect(occurrenceStartField(dialog)).toHaveValue("2017-07-08");
    await expect(dialog.getByLabel("Time zone", { exact: true })).toHaveValue(
      "America/Los_Angeles",
    );
    expect(await snapshot()).toEqual(before);
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-photo-dates-desktop.png",
      fullPage: true,
    });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await dialog
      .getByRole("button", {
        name: "Use calendar date 2017-07-08",
        exact: true,
      })
      .scrollIntoViewIfNeeded();
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-photo-dates-mobile.png",
      fullPage: true,
    });
    await dialog.getByRole("button", { name: "Close Entry editor" }).click();
    expect(await snapshot()).toEqual(before);
    await page.getByRole("button", { name: "Edit Entry", exact: true }).click();
    await expect(dialog.getByLabel("Date type")).toHaveValue("range");
    await dialog
      .getByRole("button", { name: "Show photos", exact: true })
      .click();
    await dialog
      .getByRole("button", { name: "Read camera date", exact: true })
      .click();
    await dialog
      .getByRole("button", {
        name: "Use calendar date 2017-07-08",
        exact: true,
      })
      .click();
    await dialog
      .getByRole("button", { name: "Save changes", exact: true })
      .click();
    await expect
      .poll(async () => (await snapshot()).date_precision)
      .toBe("day");
    const saved = await snapshot();
    expect(saved.occurred_start).toBe("2017-07-08T19:00:00+00:00");
    expect(saved.occurred_end).toBeNull();
    expect(saved.body).toBe(before.body);
    expect(saved.occurred_timezone).toBe(before.occurred_timezone);
    await expect(dialog).not.toBeVisible();
    await page.getByRole("button", { name: "Edit Entry", exact: true }).click();
    await fillOccurrenceStart(dialog, "2018-02-03");
    await dialog
      .getByRole("button", { name: "Save changes", exact: true })
      .click();
    await expect
      .poll(async () => (await snapshot()).occurred_start)
      .toBe("2018-02-03T20:00:00+00:00");
    const original = await client.storage.from("entry-media").download(path);
    expect(Buffer.from(await original.data!.arrayBuffer()).equals(bytes)).toBe(
      true,
    );
    expect(
      (await client.from("entry_places").select("*").eq("entry_id", entry))
        .data,
    ).toEqual([]);
    async function openPlaceDraft() {
      await expect(dialog).not.toBeVisible();
      await page
        .getByRole("button", { name: "Edit Entry", exact: true })
        .click();
      await dialog
        .getByRole("button", { name: "Show photos", exact: true })
        .click();
      await dialog
        .getByRole("button", { name: "Read camera date", exact: true })
        .click();
      await dialog
        .getByRole("button", { name: "Use GPS for a Location", exact: true })
        .click();
    }
    await openPlaceDraft();
    await expect(dialog.getByText("39.95000, -75.16667")).toBeVisible();
    await expect(dialog.getByLabel("New Location name")).toHaveCount(0);
    expect(
      (await client.from("locations").select("id").eq("owner_id", owner)).data,
    ).toEqual([]);
    await dialog.getByRole("button", { name: "Close Entry editor" }).click();
    expect(
      (await client.from("locations").select("id").eq("owner_id", owner)).data,
    ).toEqual([]);
    await openPlaceDraft();
    await expect(dialog.getByLabel("Latitude", { exact: true })).toHaveCount(0);
    await expect(dialog.getByLabel("Longitude", { exact: true })).toHaveCount(
      0,
    );
    await expect(
      dialog.getByRole("button", {
        name: "Use GPS for a Location",
        exact: true,
      }),
    ).toBeDisabled();
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.emulateMedia({ colorScheme: "light" });
    await dialog.getByText("39.95000, -75.16667").scrollIntoViewIfNeeded();
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-photo-place-desktop.png",
      fullPage: true,
    });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await dialog
      .getByRole("button", { name: "Save changes", exact: true })
      .click();
    await expect(dialog).not.toBeVisible();
    const newLocation = await client
      .from("locations")
      .select("*")
      .eq("owner_id", owner)
      .single();
    expect(newLocation.data).toMatchObject({
      name: "Location not set",
      latitude: 39.95,
      longitude: -75.166667,
      bound_entry_id: entry,
    });
    expect(
      (
        await client
          .from("entry_places")
          .select("place_id")
          .eq("entry_id", entry)
      ).data,
    ).toEqual([{ place_id: newLocation.data!.id }]);
    const nativeOptions = await page.request.post(
      "/api/media/place-options?query=anything",
      { headers: bearer },
    );
    expect(nativeOptions.status()).toBe(410);
    const raceBefore = await snapshot();
    const raceInput = {
      p_entry_id: entry,
      p_expected_revision: raceBefore.revision,
      p_title: raceBefore.title,
      p_body: raceBefore.body,
      p_item_kind: "entry",
      p_item_subtype: "entry",
      p_occurred_start: raceBefore.occurred_start,
      p_occurred_timezone: raceBefore.occurred_timezone,
      p_tag_names: [],
      p_occurred_end: null,
      p_occurred_label: null,
      p_date_precision: "day",
      p_photo_place: {
        kind: "new",
        attachmentId: attachment,
        name: "Concurrent photo Location",
        latitude: 30,
        longitude: 40,
      },
      p_primary_location: null,
      p_body_rich: null,
    };
    const race = await Promise.all([
      client.rpc("review_wiki_item_with_location_rich", raceInput),
      client.rpc("review_wiki_item_with_location_rich", raceInput),
    ]);
    expect(race.map((v) => v.error)).toEqual([null, null]);
    expect(race.map((v) => v.data.length).sort()).toEqual([0, 1]);
    expect(
      (
        await client
          .from("locations")
          .select("id")
          .eq("owner_id", owner)
          .eq("latitude", 30)
          .eq("longitude", 40)
      ).data,
    ).toHaveLength(1);
    expect(
      (
        await client.rpc("trash_entry_attachment", {
          p_attachment_id: attachment,
        })
      ).error,
    ).toBeNull();
    expect(
      (await page.request.post(endpoint, { headers: bearer })).status(),
    ).toBe(404);
  } finally {
    await cleanupMediaFixture(admin, owner, env.API_URL);
    if (otherOwner)
      expect((await admin.auth.admin.deleteUser(otherOwner)).error).toBeNull();
  }
});
