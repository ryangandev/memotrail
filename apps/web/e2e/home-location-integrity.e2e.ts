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
    await expect(
      page
        .getByRole("button", { name: /Home without coordinates/ })
        .locator('[data-record-card-map="true"]'),
    ).toHaveCount(0);

    await page.getByRole("button", { name: "Add Home" }).first().click();
    const mappedHome = page.getByRole("dialog");
    await mappedHome
      .getByRole("textbox", { name: "Home name" })
      .fill("Mapped Pine Home");
    await mappedHome
      .getByRole("combobox", { name: "Find a Location" })
      .fill("Pine Street");
    await mappedHome.getByRole("option", { name: /10 Pine Street/ }).click();
    await mappedHome.getByRole("button", { name: "Add Home" }).click();
    await expect(mappedHome).not.toBeVisible();
    const mappedCard = page.getByRole("button", { name: /Mapped Pine Home/ });
    const map = mappedCard.locator('[data-record-card-map="true"]');
    await expect(map).toBeVisible();
    await expect
      .poll(() => map.evaluate((img: HTMLImageElement) => img.naturalWidth))
      .toBeGreaterThan(0);
    const cardMap = await page.request.get((await map.getAttribute("src"))!);
    expect(cardMap.status()).toBe(200);
    expect(await cardMap.text()).not.toContain("<text");
    await mappedCard.screenshot({
      path: "/private/tmp/memotrail-home-map-card-desktop.png",
    });

    await mappedCard.click();
    await expect(
      page.getByRole("heading", { name: "Mapped Pine Home" }),
    ).toBeVisible();
    await expect(page.getByRole("link", { name: "Back to homes" })).toHaveCount(
      0,
    );
    const editHome = page.getByRole("button", { name: "Edit Home" });
    await expect(editHome).toHaveText("Edit");
    await expect(editHome.locator("svg")).toHaveCount(1);
    await editHome.click();
    const providerEdit = page.getByRole("main");
    await providerEdit
      .getByRole("combobox", { name: "Change Location" })
      .fill("Pine Street");
    await providerEdit.getByRole("option", { name: /10 Pine Street/ }).click();
    await providerEdit.getByRole("button", { name: "Save changes" }).click();
    await expect(editHome).toBeVisible();
    await page.goto("/homes");
    await expect(
      mappedCard.locator('[data-record-card-map="true"]'),
    ).toBeVisible();

    const mappedEntry = (
      await admin
        .from("entries")
        .select("id,revision")
        .eq("owner_id", owner)
        .eq("title", "Mapped Pine Home")
        .single()
    ).data!;
    await mappedCard.click();
    await page.getByRole("button", { name: "Edit Home" }).click();
    const staleEdit = page.getByRole("main");
    expect(
      (
        await admin
          .from("entries")
          .update({ revision: mappedEntry.revision + 1 })
          .eq("id", mappedEntry.id)
      ).error,
    ).toBeNull();
    await staleEdit
      .getByRole("textbox", { name: "Home name" })
      .fill("Stale edit");
    await staleEdit.getByRole("button", { name: "Save changes" }).click();
    await expect(staleEdit.locator("footer [role=alert]")).toContainText(
      "changed on another device",
    );
    await staleEdit.screenshot({
      path: "/private/tmp/memotrail-home-save-error.png",
    });
    await staleEdit.getByRole("button", { name: "Cancel" }).click();
    await page.goto("/homes");

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
    await expect(
      page
        .getByRole("button", { name: /Edited Pine Home/ })
        .locator('[data-record-card-map="true"]'),
    ).toHaveCount(0);
  } finally {
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
