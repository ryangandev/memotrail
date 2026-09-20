import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

test("one Entry can replace a shared Location without rewriting the other", async ({
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
  const email = `location-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  const owner = created.data.user!.id;
  const firstEntryId = randomUUID();
  const secondEntryId = randomUUID();
  const sharedLocationId = randomUUID();

  try {
    const cookies: { name: string; value: string }[] = [];
    const client = createServerClient(env.API_URL, env.ANON_KEY, {
      cookies: {
        getAll: () => cookies,
        setAll: (values) => {
          cookies.push(
            ...values.map((value) => ({
              name: value.name,
              value: value.value,
            })),
          );
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

    expect(
      (
        await client.from("locations").insert({
          id: sharedLocationId,
          owner_id: owner,
          name: "Shared Pine Street",
          formatted_address: "10 Pine Street, Philadelphia, PA",
          address: "10 Pine Street",
          city: "Philadelphia",
          region: "Pennsylvania",
          country: "United States",
          country_code: "us",
          latitude: 39.9526,
          longitude: -75.1652,
          timezone_id: "America/New_York",
          result_type: "building",
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("entries").insert([
          {
            id: firstEntryId,
            owner_id: owner,
            title: "The day on Pine Street",
            body: "First memory",
            item_kind: "writing",
            item_subtype: "note",
            inbox_status: "organized",
            date_precision: "unknown",
          },
          {
            id: secondEntryId,
            owner_id: owner,
            title: "Another Pine Street memory",
            body: "Second memory",
            item_kind: "writing",
            item_subtype: "note",
            inbox_status: "organized",
            date_precision: "unknown",
          },
        ])
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("entry_places").insert([
          {
            entry_id: firstEntryId,
            owner_id: owner,
            place_id: sharedLocationId,
            relationship: "primary",
          },
          {
            entry_id: secondEntryId,
            owner_id: owner,
            place_id: sharedLocationId,
            relationship: "primary",
          },
        ])
      ).error,
    ).toBeNull();

    await page.route("**/api/locations/search**", async (route) => {
      await route.fulfill({
        contentType: "application/json",
        json: {
          configured: true,
          providerUnavailable: false,
          saved: [],
          provider: [
            {
              kind: "provider",
              provider: "geoapify",
              providerLocationId: "synthetic-market-street",
              name: "Reading Terminal Market",
              formattedAddress:
                "1136 Arch Street, Philadelphia, PA 19107, United States",
              address: "1136 Arch Street",
              city: "Philadelphia",
              region: "Pennsylvania",
              postalCode: "19107",
              country: "United States",
              countryCode: "us",
              latitude: 39.9533,
              longitude: -75.1593,
              timezone: "America/New_York",
              resultType: "amenity",
              confidence: 0.99,
              matchType: "full_match",
              dataSource: "openstreetmap",
            },
          ],
        },
      });
    });

    await page.goto(`/history?entry=${firstEntryId}`);
    await page
      .getByRole("button", { name: "Edit Writing", exact: true })
      .click();
    const dialog = page.getByRole("dialog");
    await expect(
      dialog.getByRole("img", { name: "Map showing Shared Pine Street" }),
    ).toBeVisible();
    await dialog
      .getByRole("textbox", { name: "Change Location" })
      .fill("Reading Terminal");
    await dialog.getByRole("button", { name: "Search", exact: true }).click();
    await dialog
      .getByRole("button", { name: /Reading Terminal Market/ })
      .click();
    await expect(
      dialog.getByRole("img", { name: "Map showing Reading Terminal Market" }),
    ).toBeVisible();
    await expect(dialog.getByText("39.95330, -75.15930")).toBeVisible();
    await page.screenshot({
      animations: "disabled",
      caret: "hide",
      path: "/private/tmp/memotrail-location-editor.png",
    });
    await page.setViewportSize({ height: 844, width: 390 });
    expect(
      await dialog.evaluate(
        (element) => element.scrollWidth <= element.clientWidth + 1,
      ),
    ).toBe(true);
    await page.screenshot({
      animations: "disabled",
      caret: "hide",
      path: "/private/tmp/memotrail-location-editor-mobile.png",
    });
    await dialog
      .getByRole("button", { name: "Save changes", exact: true })
      .click();
    await expect(dialog).not.toBeVisible();

    const providerLocation = (
      await client
        .from("locations")
        .select("id,name,provider,provider_location_id")
        .eq("provider", "geoapify")
        .eq("provider_location_id", "synthetic-market-street")
        .single()
    ).data!;
    expect(providerLocation).toMatchObject({
      name: "Reading Terminal Market",
      provider: "geoapify",
    });
    const links = (
      await client
        .from("entry_places")
        .select("entry_id,place_id,relationship")
        .in("entry_id", [firstEntryId, secondEntryId])
        .eq("relationship", "primary")
    ).data!;
    expect(links).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          entry_id: firstEntryId,
          place_id: providerLocation.id,
        }),
        expect.objectContaining({
          entry_id: secondEntryId,
          place_id: sharedLocationId,
        }),
      ]),
    );
    expect(
      (
        await client
          .from("locations")
          .select("name,formatted_address")
          .eq("id", sharedLocationId)
          .single()
      ).data,
    ).toEqual({
      name: "Shared Pine Street",
      formatted_address: "10 Pine Street, Philadelphia, PA",
    });

    await page.setViewportSize({ height: 900, width: 1280 });
    await page.goto("/homes");
    await page.getByRole("button", { name: "Add Home" }).first().click();
    const homeDialog = page.getByRole("dialog");
    await homeDialog
      .getByRole("textbox", { name: "Home name" })
      .fill("Market Street Home");
    await homeDialog
      .getByRole("textbox", { name: "Find a Location" })
      .fill("Reading Terminal");
    await expect(
      homeDialog.getByRole("button", { name: /Reading Terminal Market/ }),
    ).toBeVisible();
    await homeDialog
      .getByRole("button", { name: /Reading Terminal Market/ })
      .click();
    await expect(
      homeDialog.getByRole("img", {
        name: "Map showing Reading Terminal Market",
      }),
    ).toBeVisible();
    await expect(homeDialog.getByText("39.95330, -75.15930")).toBeVisible();
    await expect(
      homeDialog.getByRole("textbox", { name: "Location name" }),
    ).toHaveValue("Reading Terminal Market");
    await page.screenshot({
      animations: "disabled",
      caret: "hide",
      path: "/private/tmp/memotrail-home-location-editor.png",
    });
    await homeDialog.getByRole("button", { name: "Add Home" }).click();
    await expect(homeDialog).not.toBeVisible();

    const homeLocation = (
      await client
        .from("homes")
        .select("place_id")
        .eq("owner_id", owner)
        .single()
    ).data;
    expect(homeLocation?.place_id).toBe(providerLocation.id);
  } finally {
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
