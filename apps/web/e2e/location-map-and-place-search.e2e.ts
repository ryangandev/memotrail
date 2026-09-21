import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

test("Map shows current Entry coordinates and Place search only fills its form", async ({
  context,
  page,
}) => {
  const env = JSON.parse(
    execFileSync("supabase", ["status", "-o", "json"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }),
  );
  const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY);
  const email = `map-place-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
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
        httpOnly: false,
        path: "/",
        sameSite: "Lax",
      })),
    );

    const eventId = randomUUID();
    const writingId = randomUUID();
    const deletedId = randomUUID();
    const eventLocationId = randomUUID();
    const writingLocationId = randomUUID();
    const deletedLocationId = randomUUID();
    expect(
      (
        await client.from("entries").insert([
          {
            id: eventId,
            owner_id: owner,
            title: "A day at Pine Street",
            body: "An event",
            item_kind: "event",
            item_subtype: "first_time",
            inbox_status: "organized",
            date_precision: "day",
            occurred_start: "2020-06-01T00:00:00Z",
          },
          {
            id: writingId,
            owner_id: owner,
            title: "Pine Street journal",
            body: "A memory",
            item_kind: "writing",
            item_subtype: "note",
            inbox_status: "organized",
            date_precision: "year",
            occurred_start: "2022-01-01T00:00:00Z",
          },
          {
            id: deletedId,
            owner_id: owner,
            title: "Deleted Pine Street note",
            body: "Hidden from map",
            item_kind: "writing",
            item_subtype: "note",
            inbox_status: "organized",
            date_precision: "unknown",
            deleted_at: new Date().toISOString(),
          },
        ])
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("locations").insert(
          [
            [eventLocationId, eventId],
            [writingLocationId, writingId],
            [deletedLocationId, deletedId],
          ].map(([id, entryId]) => ({
            id,
            owner_id: owner,
            bound_entry_id: entryId,
            name: "10 Pine Street",
            formatted_address: "10 Pine Street, Philadelphia, PA",
            address: "10 Pine Street",
            city: "Philadelphia",
            latitude: 39.9526,
            longitude: -75.1652,
          })),
        )
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("entry_places").insert([
          {
            owner_id: owner,
            entry_id: eventId,
            place_id: eventLocationId,
            relationship: "primary",
          },
          {
            owner_id: owner,
            entry_id: eventId,
            place_id: eventLocationId,
            relationship: "related",
          },
          {
            owner_id: owner,
            entry_id: writingId,
            place_id: writingLocationId,
            relationship: "related",
          },
          {
            owner_id: owner,
            entry_id: deletedId,
            place_id: deletedLocationId,
            relationship: "primary",
          },
        ])
      ).error,
    ).toBeNull();

    await page.goto("/first-times");
    await expect(
      page
        .getByRole("button", { name: /A day at Pine Street/ })
        .locator('[data-record-card-map="true"]'),
    ).toBeVisible();

    await page.goto("/map");
    await expect(
      page.getByRole("status").filter({ hasText: "2 Entry Locations" }),
    ).toBeVisible();
    await expect(page.locator(".leaflet-marker-icon")).toHaveCount(1);
    await page.locator(".leaflet-marker-icon").click();
    await expect(
      page.getByRole("link", { name: /A day at Pine Street/ }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: /Pine Street journal/ }),
    ).toBeVisible();
    await expect(page.getByText("Deleted Pine Street note")).toHaveCount(0);
    await page.screenshot({
      animations: "disabled",
      path: "/private/tmp/memotrail-location-map-desktop.png",
    });

    await page.getByLabel("Kind").selectOption("event");
    await expect(
      page.getByRole("status").filter({ hasText: "1 Entry Location" }),
    ).toBeVisible();
    await page.locator(".leaflet-marker-icon").click();
    await expect(
      page.getByRole("link", { name: /A day at Pine Street/ }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: /Pine Street journal/ }),
    ).toHaveCount(0);
    await page.getByLabel("From year").fill("2021");
    await expect(
      page.getByRole("status").filter({ hasText: "0 Entry Locations" }),
    ).toBeVisible();

    await page.setViewportSize({ width: 390, height: 844 });
    await page.getByLabel("Kind").selectOption("all");
    await page.getByLabel("From year").fill("");
    await expect(page.locator(".leaflet-marker-icon")).toHaveCount(1);
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth + 1,
      ),
    ).toBe(true);
    await page.screenshot({
      animations: "disabled",
      path: "/private/tmp/memotrail-location-map-mobile.png",
    });

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
              providerLocationId: "pine-cafe",
              name: "20 Pine Street, Philadelphia, PA",
              formattedAddress: "20 Pine Street, Philadelphia, PA",
              address: "20 Pine Street",
              city: "Philadelphia",
              region: "Pennsylvania",
              postalCode: null,
              country: "United States",
              countryCode: "us",
              latitude: 39.9527,
              longitude: -75.1653,
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
    await page.goto("/places");
    await page.getByRole("button", { name: "Add Place" }).first().click();
    const editor = page.getByRole("dialog");
    await editor.getByRole("textbox", { name: "Name" }).fill("The corner café");
    const addressSearch = editor.getByRole("combobox", {
      name: "Find an address for this Place",
    });
    await addressSearch.fill("20 Pine");
    await expect(
      editor.getByRole("option", { name: /20 Pine Street/ }),
    ).toBeVisible();
    await addressSearch.press("ArrowDown");
    await expect(addressSearch).toHaveAttribute("aria-activedescendant", /.+/);
    await addressSearch.press("Enter");
    await expect(
      editor.getByRole("img", { name: /Map preview for The corner café/ }),
    ).toBeVisible();
    await editor.getByRole("button", { name: "Add Place" }).click();
    await expect(editor).not.toBeVisible();
    const place = (
      await client
        .from("places")
        .select("name,address,city,latitude,longitude")
        .eq("owner_id", owner)
        .single()
    ).data;
    expect(place).toMatchObject({
      name: "The corner café",
      address: "20 Pine Street",
      city: "Philadelphia",
      latitude: 39.9527,
      longitude: -75.1653,
    });
    await expect(
      page
        .getByRole("button", { name: /The corner café/ })
        .locator('[data-record-card-map="true"]'),
    ).toBeVisible();
    const locations = await client
      .from("locations")
      .select("id", { count: "exact", head: true })
      .eq("owner_id", owner);
    expect(locations.count).toBe(3);
  } finally {
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
