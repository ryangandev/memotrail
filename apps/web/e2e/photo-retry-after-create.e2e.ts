import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test, type Page } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import sharp from "sharp";
import { cleanupMediaFixture } from "./helpers/media-fixture";

const scenarios = [
  { name: "Goal from a Capture", kind: "goal", capture: true, provider: false },
  { name: "Home from a Capture", kind: "home", capture: true, provider: false },
  {
    name: "Vehicle from a Capture",
    kind: "vehicle",
    capture: true,
    provider: false,
  },
  {
    name: "Home with a provider address",
    kind: "home",
    capture: false,
    provider: true,
  },
  {
    name: "Home from a Capture with a provider address",
    kind: "home",
    capture: true,
    provider: true,
  },
  {
    name: "Vehicle from a Capture with a provider Location",
    kind: "vehicle",
    capture: true,
    provider: true,
  },
] as const;

const records = {
  goal: {
    add: "Add to Want to Do",
    captureDialog: "Add this Capture to Want to Do",
    partial: "Saved",
    saved: "Changes saved.",
    path: "/goals",
    itemKind: "goal",
    subtype: "goal",
  },
  home: {
    add: "Add Home",
    captureDialog: "Create a Home from this Capture",
    partial: "The Home was saved",
    saved: "Home saved.",
    path: "/homes",
    itemKind: "entity",
    subtype: "home",
  },
  vehicle: {
    add: "Add Vehicle",
    captureDialog: "Create a Vehicle from this Capture",
    partial: "The Vehicle was saved",
    saved: "Vehicle saved.",
    path: "/vehicles",
    itemKind: "entity",
    subtype: "vehicle",
  },
} as const;

// Hydration, saves, and uploads can be slow on a busy machine.
const slow = { timeout: 30_000 };

for (const scenario of scenarios) {
  test(`${scenario.name} retries a failed photo as an update of the created record`, async ({
    context,
    page,
  }) => {
    test.setTimeout(120_000);
    const uiErrors: string[] = [];
    page.on("pageerror", (error) => uiErrors.push(error.message));
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
      email: `media-retry-${randomUUID()}@memotrail.local`,
      email_confirm: true,
    });
    expect(created.error).toBeNull();
    const owner = created.data.user!.id;
    const record = records[scenario.kind];
    const title = `Retry ${record.subtype} fixture`;

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
          httpOnly: false,
          path: "/",
          sameSite: "Lax" as const,
        })),
      );
      if (scenario.provider) await mockProviderSearch(page);

      const captureID = randomUUID();
      const capturedAt = "2024-03-05T08:31:00+00:00";
      const editor = page.getByRole("dialog");
      if (scenario.capture) {
        expect(
          (
            await client.from("entries").insert({
              id: captureID,
              owner_id: owner,
              title,
              body: "Started as an Inbox Capture.",
              item_kind: "entry",
              item_subtype: "entry",
              inbox_status: "unreviewed",
              // A day-precision date keeps its captured time unless it is edited.
              date_precision: "day",
              occurred_start: capturedAt,
              occurred_timezone: "UTC",
            })
          ).error,
        ).toBeNull();
        await page.goto(`${record.path}?source=${captureID}`);
        // The shared Dialog mounts only on the client, so it appears once the page hydrates.
        await expect(
          page.getByRole("dialog", {
            name: record.captureDialog,
          }),
        ).toBeVisible(slow);
        await expect(
          editor.getByText("Starting from an Inbox Capture"),
        ).toBeVisible();
      } else {
        await page.goto(record.path);
        // The page is server rendered, so a click before hydration opens nothing.
        await expect(async () => {
          if (!(await editor.isVisible())) {
            await page
              .getByRole("button", { name: record.add })
              .first()
              .click();
          }
          await expect(editor).toBeVisible({ timeout: 2_000 });
        }).toPass(slow);
        await editor.getByRole("textbox", { name: "Home name" }).fill(title);
      }
      if (scenario.provider) {
        await editor
          .getByRole("combobox", { name: "Find a Location" })
          .fill("Pine Street");
        await editor.getByRole("option", { name: /10 Pine Street/ }).click();
      }

      const photos = await Promise.all(
        [
          { name: "first.png", background: "#316652" },
          { name: "second.png", background: "#8a3b2f" },
        ].map(async ({ name, background }) => ({
          name,
          mimeType: "image/png",
          buffer: await sharp({
            create: { width: 40, height: 24, channels: 3, background },
          })
            .png()
            .toBuffer(),
        })),
      );
      await editor.locator('input[type="file"]').setInputFiles(photos);

      // The first original never reaches Storage, so its registration fails after the record exists.
      let failedUploads = 0;
      await page.route("**/storage/v1/object/entry-media/**", async (route) => {
        if (route.request().method() === "POST" && failedUploads === 0) {
          failedUploads += 1;
          await route.abort("failed");
        } else await route.continue();
      });
      await editor
        .getByRole("button", { name: record.add, exact: true })
        .click();
      await expect(
        editor.getByText(
          `${record.partial}, but 1 photo could not be attached. Select Save again to retry.`,
        ),
      ).toBeVisible(slow);
      expect(failedUploads).toBe(1);

      const saved = await client
        .from("entries")
        .select("id")
        .eq("owner_id", owner)
        .eq("item_kind", record.itemKind)
        .eq("item_subtype", record.subtype)
        .single();
      expect(saved.error).toBeNull();
      const entryID = saved.data!.id;
      const createdLocations = await savedLocations(
        client,
        scenario.kind,
        entryID,
      );
      expect(createdLocations).toHaveLength(scenario.provider ? 1 : 0);

      // A record that exists is updated; the Capture handoff and provider choice belong only to creation.
      await expect(
        editor.getByRole("heading", { name: title, exact: true }),
      ).toBeVisible();
      await expect(
        editor.getByText("Starting from an Inbox Capture"),
      ).toHaveCount(0);
      await expect(editor.locator('img[alt^="Selected "]')).toHaveCount(1);
      await editor
        .getByRole("button", { name: "Save changes", exact: true })
        .click();
      await expect(editor).not.toBeVisible(slow);
      await expect(page.getByText(record.saved)).toBeVisible();

      const entries = await client
        .from("entries")
        .select("id,title,occurred_start")
        .eq("owner_id", owner)
        .eq("item_kind", record.itemKind)
        .eq("item_subtype", record.subtype);
      expect(entries.data).toEqual([
        {
          id: entryID,
          title,
          occurred_start:
            scenario.capture && scenario.kind !== "goal" ? capturedAt : null,
        },
      ]);
      const attached = await client
        .from("attachments")
        .select("object_path,original_filename")
        .eq("entry_id", entryID)
        .eq("variant", "original")
        .is("deleted_at", null)
        .order("original_filename");
      expect(attached.error).toBeNull();
      expect(attached.data?.map((photo) => photo.original_filename)).toEqual([
        "first.png",
        "second.png",
      ]);
      for (const photo of attached.data!) {
        const original = await client.storage
          .from("entry-media")
          .download(photo.object_path);
        expect(original.error).toBeNull();
        expect(Buffer.from(await original.data!.arrayBuffer())).toEqual(
          photos.find((item) => item.name === photo.original_filename)!.buffer,
        );
      }

      if (scenario.capture) {
        const capture = await client
          .from("entries")
          .select("inbox_status,item_subtype")
          .eq("id", captureID)
          .single();
        expect(capture.data).toEqual({
          inbox_status: "organized",
          item_subtype: "source_capture",
        });
        const provenance = await client
          .from("entry_links")
          .select("source_entry_id,target_entry_id,relationship")
          .eq("owner_id", owner)
          .in("relationship", ["derived", "derived_from"])
          .order("relationship");
        expect(provenance.data).toEqual([
          {
            source_entry_id: captureID,
            target_entry_id: entryID,
            relationship: "derived",
          },
          {
            source_entry_id: entryID,
            target_entry_id: captureID,
            relationship: "derived_from",
          },
        ]);
        // Closing the editor consumes the handoff instead of leaving it in the URL.
        await expect(page).toHaveURL(record.path, slow);
      }

      // The retry keeps the provider snapshot made on creation instead of copying it.
      expect(await savedLocations(client, scenario.kind, entryID)).toEqual(
        createdLocations,
      );
      const locations = await client
        .from("locations")
        .select("id,provider,provider_location_id,address,latitude")
        .eq("owner_id", owner);
      expect(locations.data).toEqual(
        scenario.provider
          ? [
              {
                id: createdLocations[0],
                provider: "geoapify",
                provider_location_id: "synthetic-retry-address",
                address: "10 Pine Street",
                latitude: 39.952612,
              },
            ]
          : [],
      );
      expect(uiErrors).toEqual([]);
    } finally {
      await cleanupMediaFixture(admin, owner, env.API_URL);
    }
  });
}

async function savedLocations(
  client: SupabaseClient,
  kind: keyof typeof records,
  entryID: string,
) {
  if (kind === "goal") return [];
  const links =
    kind === "home"
      ? await client.from("homes").select("place_id").eq("entry_id", entryID)
      : await client
          .from("entry_places")
          .select("place_id")
          .eq("entry_id", entryID)
          .eq("relationship", "primary");
  expect(links.error).toBeNull();
  return links
    .data!.map((link) => link.place_id as string | null)
    .filter((id): id is string => id !== null);
}

async function mockProviderSearch(page: Page) {
  await page.route("**/api/locations/search**", async (route) => {
    await route.fulfill({
      contentType: "application/json",
      json: {
        configured: true,
        providerUnavailable: false,
        provider: [
          {
            kind: "provider",
            provider: "geoapify",
            providerLocationId: "synthetic-retry-address",
            name: "10 Pine Street, Philadelphia, PA",
            formattedAddress: "10 Pine Street, Philadelphia, PA",
            address: "10 Pine Street",
            city: "Philadelphia",
            region: "Pennsylvania",
            postalCode: null,
            country: "United States",
            countryCode: "us",
            latitude: 39.95261234,
            longitude: -75.16529876,
            timezone: "America/New_York",
            resultType: "building",
            confidence: 0.99,
            matchType: "full_match",
            dataSource: "openstreetmap",
          },
        ],
      },
    });
  });
}
