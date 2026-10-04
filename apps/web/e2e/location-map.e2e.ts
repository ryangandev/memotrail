import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

test("Map shows current Entry coordinates", async ({ context, page }) => {
  const env = JSON.parse(
    execFileSync("supabase", ["status", "-o", "json"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }),
  );
  const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY);
  const email = `map-location-${randomUUID()}@memotrail.local`;
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
    await context.addCookies([
      {
        name: "memotrail-theme",
        value: "dark",
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax",
      },
    ]);

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
            item_kind: "entry",
            item_subtype: "first_time",
            date_precision: "day",
            occurred_start: "2020-06-01T00:00:00Z",
          },
          {
            id: writingId,
            owner_id: owner,
            title: "Pine Street journal",
            body: "A memory",
            item_kind: "entry",
            item_subtype: "entry",
            date_precision: "year",
            occurred_start: "2022-01-01T00:00:00Z",
          },
          {
            id: deletedId,
            owner_id: owner,
            title: "Deleted Pine Street note",
            body: "Hidden from map",
            item_kind: "entry",
            item_subtype: "entry",
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
    await expect(
      page
        .getByRole("button", { name: /A day at Pine Street/ })
        .locator('[data-record-card-map="true"]'),
    ).toHaveAttribute("src", /theme=dark/);

    const darkTile =
      process.env.MEMOTRAIL_E2E_LIVE_GEOAPIFY === "1"
        ? page.waitForResponse(
            (response) =>
              response.url().includes("/api/locations/tiles/") &&
              response.url().includes("theme=dark") &&
              response.status() === 200,
          )
        : null;
    await page.goto("/map");
    await expect(
      page.getByRole("region", {
        name: "Interactive map of your Entry Locations",
      }),
    ).toHaveAttribute("data-map-theme", "dark");
    if (darkTile) {
      await darkTile;
      await page.waitForFunction(() => {
        const tiles = [...document.querySelectorAll(".leaflet-tile")];
        return (
          tiles.length >= 4 &&
          tiles.every((tile) => tile.classList.contains("leaflet-tile-loaded"))
        );
      });
      await page.waitForLoadState("networkidle");
      await expect(
        page.getByText("Some map tiles are unavailable right now."),
      ).toHaveCount(0);
      await page.screenshot({
        animations: "disabled",
        path: "/private/tmp/memotrail-location-map-dark.png",
      });
    }
    const lightTile =
      process.env.MEMOTRAIL_E2E_LIVE_GEOAPIFY === "1"
        ? page.waitForResponse(
            (response) =>
              response.url().includes("/api/locations/tiles/") &&
              response.url().includes("theme=light") &&
              response.status() === 200,
          )
        : null;
    await page.evaluate(() =>
      document.documentElement.setAttribute("data-theme", "light"),
    );
    await expect(
      page.getByRole("region", {
        name: "Interactive map of your Entry Locations",
      }),
    ).toHaveAttribute("data-map-theme", "light");
    if (lightTile) await lightTile;
    await page.emulateMedia({ colorScheme: "dark" });
    await page.evaluate(() =>
      document.documentElement.removeAttribute("data-theme"),
    );
    await expect(
      page.getByRole("region", {
        name: "Interactive map of your Entry Locations",
      }),
    ).toHaveAttribute("data-map-theme", "dark");
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

    await page.getByLabel("Category").selectOption("entry");
    await expect(
      page.getByRole("status").filter({ hasText: "2 Entry Locations" }),
    ).toBeVisible();
    await page.locator(".leaflet-marker-icon").click();
    await expect(
      page.getByRole("link", { name: /A day at Pine Street/ }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: /Pine Street journal/ }),
    ).toBeVisible();
    await page.getByLabel("From year").fill("2023");
    await expect(
      page.getByRole("status").filter({ hasText: "0 Entry Locations" }),
    ).toBeVisible();

    await page.setViewportSize({ width: 390, height: 844 });
    await page.getByLabel("Category").selectOption("all");
    await page.getByLabel("From year").fill("");
    await expect(page.locator(".leaflet-marker-icon")).toHaveCount(1);
    await expect
      .poll(() =>
        page.evaluate(
          () => document.documentElement.scrollWidth <= window.innerWidth + 1,
        ),
      )
      .toBe(true);
    await page.screenshot({
      animations: "disabled",
      path: "/private/tmp/memotrail-location-map-mobile.png",
    });

    const westEntryId = randomUUID();
    const westLocationId = randomUUID();
    expect(
      (
        await client.from("entries").insert({
          id: westEntryId,
          owner_id: owner,
          title: "Walk by the bay",
          body: "A San Francisco memory",
          item_kind: "entry",
          item_subtype: "entry",
          date_precision: "year",
          occurred_start: "2024-01-01T00:00:00Z",
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("locations").insert({
          id: westLocationId,
          owner_id: owner,
          bound_entry_id: westEntryId,
          name: "San Francisco Bay",
          formatted_address: "San Francisco, California",
          city: "San Francisco",
          region: "California",
          country: "United States",
          latitude: 37.7749,
          longitude: -122.4194,
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("entry_places").insert({
          owner_id: owner,
          entry_id: westEntryId,
          place_id: westLocationId,
          relationship: "primary",
        })
      ).error,
    ).toBeNull();

    await page.setViewportSize({ width: 1280, height: 900 });
    await page.reload();
    await expect(
      page.getByRole("heading", { name: "Your areas" }),
    ).toBeVisible();
    const eastArea = page.getByRole("button", {
      name: "Zoom to Philadelphia, 2 Entries",
    });
    const westArea = page.getByRole("button", {
      name: "Zoom to San Francisco, California, 1 Entry",
    });
    await expect(eastArea).toBeVisible();
    await expect(westArea).toBeVisible();
    await expect(page.locator(".leaflet-marker-icon")).toHaveCount(2);
    await eastArea.click();
    await expect(page.locator(".leaflet-marker-icon")).toHaveCount(1);
    await expect(page.locator(".leaflet-marker-icon")).toHaveAttribute(
      "title",
      "2 Entry locations in this area",
    );
    await westArea.click();
    await expect(page.locator(".leaflet-marker-icon")).toHaveCount(1);
    await expect(page.locator(".leaflet-marker-icon")).toHaveAttribute(
      "title",
      "Walk by the bay",
    );
    await page.getByRole("button", { name: "View all" }).click();
    await expect(page.locator(".leaflet-marker-icon")).toHaveCount(2);
    await page.getByLabel("From year").fill("2023");
    await expect(page.getByRole("heading", { name: "Your areas" })).toHaveCount(
      0,
    );
    await expect(
      page.getByRole("status").filter({ hasText: "1 Entry Location" }),
    ).toBeVisible();
    await page.getByLabel("From year").fill("");
    await expect(page.locator(".leaflet-marker-icon")).toHaveCount(2);
    await page.screenshot({
      animations: "disabled",
      path: "/private/tmp/memotrail-location-map-areas-desktop.png",
    });
    await page.setViewportSize({ width: 390, height: 844 });
    await expect
      .poll(() =>
        page.evaluate(
          () => document.documentElement.scrollWidth <= window.innerWidth + 1,
        ),
      )
      .toBe(true);
    await page.screenshot({
      animations: "disabled",
      path: "/private/tmp/memotrail-location-map-areas-mobile.png",
    });
  } finally {
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
