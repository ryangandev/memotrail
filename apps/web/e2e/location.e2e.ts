import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

test("repeating an address creates independent Entry and Home Locations", async ({
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
        await client.from("entries").insert([
          {
            id: firstEntryId,
            owner_id: owner,
            title: "The day on Pine Street",
            body: "First memory",
            item_kind: "entry",
            item_subtype: "entry",
            inbox_status: "organized",
            date_precision: "unknown",
          },
          {
            id: secondEntryId,
            owner_id: owner,
            title: "Another Pine Street memory",
            body: "Second memory",
            item_kind: "entry",
            item_subtype: "entry",
            inbox_status: "organized",
            date_precision: "unknown",
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
          provider: [
            {
              kind: "provider",
              provider: "geoapify",
              providerLocationId: "synthetic-market-street",
              name: "1136 Arch Street, Philadelphia, PA 19107, United States",
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
    await page.getByRole("button", { name: "Edit Entry", exact: true }).click();
    const dialog = page.getByRole("dialog");
    await expect(dialog.getByPlaceholder("Search for an address")).toHaveCSS(
      "border-top-width",
      "0px",
    );
    await dialog.getByPlaceholder("Search for an address").focus();
    await expect(dialog.getByPlaceholder("Search for an address")).toHaveCSS(
      "box-shadow",
      "none",
    );
    await dialog
      .getByRole("combobox", { name: "Find a Location" })
      .fill("Reading Terminal");
    await dialog.getByRole("button", { name: "Search", exact: true }).click();
    await dialog.getByRole("option", { name: /1136 Arch Street/ }).click();
    await expect(
      dialog.getByRole("img", { name: /Map showing 1136 Arch Street/ }),
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

    const firstLocation = (
      await client
        .from("locations")
        .select("id,name,provider,provider_location_id,bound_entry_id")
        .eq("provider", "geoapify")
        .eq("provider_location_id", "synthetic-market-street")
        .single()
    ).data!;
    expect(firstLocation).toMatchObject({
      name: "1136 Arch Street, Philadelphia, PA 19107, United States",
      provider: "geoapify",
      bound_entry_id: firstEntryId,
    });
    expect(
      await (
        await page.request.post("/api/locations/search?query=Arch")
      ).json(),
    ).toEqual({
      configured: false,
      provider: [],
      providerUnavailable: false,
    });

    await page.goto(`/history?entry=${secondEntryId}`);
    await page.getByRole("button", { name: "Edit Entry", exact: true }).click();
    const secondDialog = page.getByRole("dialog");
    await secondDialog
      .getByRole("combobox", { name: "Find a Location" })
      .fill("Reading Terminal");
    await secondDialog
      .getByRole("option", { name: /1136 Arch Street/ })
      .click();
    await secondDialog
      .getByRole("button", { name: "Save changes", exact: true })
      .click();
    await expect(secondDialog).not.toBeVisible();

    const entryLocations = (
      await client
        .from("locations")
        .select("id,bound_entry_id")
        .eq("provider_location_id", "synthetic-market-street")
    ).data!;
    expect(entryLocations).toHaveLength(2);
    expect(new Set(entryLocations.map((location) => location.id)).size).toBe(2);
    expect(
      entryLocations.map((location) => location.bound_entry_id).sort(),
    ).toEqual([firstEntryId, secondEntryId].sort());
    expect(
      (
        await client.from("entry_places").insert({
          entry_id: secondEntryId,
          owner_id: owner,
          place_id: firstLocation.id,
          relationship: "related",
        })
      ).error?.message,
    ).toContain("location_belongs_to_another_entry");

    await page.setViewportSize({ height: 900, width: 1280 });
    await page.goto("/homes");
    await page.getByRole("button", { name: "Add Home" }).first().click();
    const homeDialog = page.getByRole("dialog");
    await expect(
      homeDialog.getByPlaceholder("Search for an address"),
    ).toHaveCSS("border-top-width", "0px");
    await homeDialog.getByPlaceholder("Search for an address").focus();
    await expect(
      homeDialog.getByPlaceholder("Search for an address"),
    ).toHaveCSS("box-shadow", "none");
    await homeDialog.locator("[data-search-field]").screenshot({
      animations: "disabled",
      path: "/private/tmp/memotrail-home-search-focused.png",
    });
    await homeDialog
      .getByRole("textbox", { name: "Home name" })
      .fill("Market Street Home");
    await homeDialog
      .getByRole("combobox", { name: "Find a Location" })
      .fill("Reading Terminal");
    await expect(
      homeDialog.getByRole("option", { name: /1136 Arch Street/ }),
    ).toBeVisible();
    await homeDialog.getByRole("option", { name: /1136 Arch Street/ }).click();
    await expect(
      homeDialog.getByRole("img", {
        name: /Map showing 1136 Arch Street/,
      }),
    ).toBeVisible();
    await expect(homeDialog.getByText("39.95330, -75.15930")).toBeVisible();
    await expect(homeDialog.getByText("Saved Location")).toHaveCount(0);
    await expect(homeDialog.getByText("Location notes")).toHaveCount(0);
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
    expect(homeLocation?.place_id).not.toBe(firstLocation.id);
    expect(entryLocations.map((location) => location.id)).not.toContain(
      homeLocation?.place_id,
    );
  } finally {
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
