import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

test("Home keeps Location optional and never pairs edited addresses with old coordinates", async ({
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
  const email = `home-location-${randomUUID()}@memotrail.local`;
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
              providerLocationId: "synthetic-home-address",
              name: "10 Pine Street, Philadelphia, PA",
              formattedAddress: "10 Pine Street, Philadelphia, PA",
              address: "10 Pine Street",
              city: "Philadelphia",
              region: "Pennsylvania",
              postalCode: null,
              country: "United States",
              countryCode: "us",
              latitude: 39.9526,
              longitude: -75.1652,
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

    await page.goto("/homes");
    await page.getByRole("button", { name: "Add Home" }).first().click();
    const emptyHome = page.getByRole("dialog");
    await emptyHome
      .getByRole("textbox", { name: "Home name" })
      .fill("Home without coordinates");
    await emptyHome.getByRole("button", { name: "Add Home" }).click();
    await expect(emptyHome).not.toBeVisible();
    const emptyRecord = (
      await client
        .from("homes")
        .select("place_id")
        .eq("owner_id", owner)
        .single()
    ).data;
    expect(emptyRecord?.place_id).toBeNull();

    await page.getByRole("button", { name: "Add Home" }).first().click();
    const editor = page.getByRole("dialog");
    await editor
      .getByRole("textbox", { name: "Home name" })
      .fill("Edited Pine Home");
    await editor
      .getByRole("combobox", { name: "Find a Location" })
      .fill("Pine Street");
    await editor.getByRole("option", { name: /10 Pine Street/ }).click();
    await editor
      .getByRole("textbox", { name: /Exact address/ })
      .fill("20 Pine Street");
    await editor.getByRole("button", { name: "Add Home" }).click();
    await expect(editor).not.toBeVisible();
    const home = (
      await client
        .from("homes")
        .select("place_id,entries!inner(title)")
        .eq("owner_id", owner)
    ).data?.find((row) => {
      const entry = row.entries as unknown as { title: string };
      return entry.title === "Edited Pine Home";
    });
    expect(home?.place_id).toBeTruthy();
    const location = (
      await client
        .from("locations")
        .select("address,latitude,longitude")
        .eq("id", home!.place_id!)
        .single()
    ).data;
    expect(location).toMatchObject({
      address: "20 Pine Street",
      latitude: null,
      longitude: null,
    });
  } finally {
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
