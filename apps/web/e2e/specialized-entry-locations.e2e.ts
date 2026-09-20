import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

test("First Time and Vehicle forms reuse a Location without changing each other", async ({
  context,
  page,
}) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
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
  const email = `specialized-location-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  const owner = created.data.user!.id;
  const locationId = randomUUID();

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
          id: locationId,
          owner_id: owner,
          name: "Shared Pine Street",
          formatted_address: "10 Pine Street, Philadelphia, PA",
          address: "10 Pine Street",
          city: "Philadelphia",
          region: "Pennsylvania",
          country: "United States",
          latitude: 39.9526,
          longitude: -75.1652,
        })
      ).error,
    ).toBeNull();

    await page.goto("/first-times");
    await page.getByRole("button", { name: "Add First Time" }).first().click();
    const firstTimeEditor = page.getByRole("dialog");
    await firstTimeEditor
      .getByRole("textbox", { name: "Title" })
      .fill("First hike");
    await firstTimeEditor
      .getByRole("searchbox", { name: "Find a Location" })
      .fill("Shared Pine");
    await firstTimeEditor
      .getByRole("button", { name: "Search", exact: true })
      .click();
    await firstTimeEditor
      .getByRole("button", { name: /Shared Pine Street/ })
      .click();
    await expect(
      firstTimeEditor.getByRole("img", {
        name: "Map showing Shared Pine Street",
      }),
    ).toBeVisible();
    const firstTimeMap = firstTimeEditor.getByRole("img", {
      name: "Map showing Shared Pine Street",
    });
    await firstTimeMap.scrollIntoViewIfNeeded();
    await expect
      .poll(() =>
        firstTimeMap.evaluate((image: HTMLImageElement) => image.naturalWidth),
      )
      .toBeGreaterThan(0);
    await page.screenshot({
      animations: "disabled",
      caret: "hide",
      path: "/private/tmp/memotrail-first-time-location-form.png",
    });
    await firstTimeEditor
      .getByRole("button", { name: "Add First Time" })
      .click();
    await expect(firstTimeEditor).not.toBeVisible();

    await page.goto("/vehicles");
    await page.getByRole("button", { name: "Add Vehicle" }).first().click();
    const vehicleEditor = page.getByRole("dialog");
    await vehicleEditor
      .getByRole("textbox", { name: "Name or nickname" })
      .fill("Blue Civic");
    await vehicleEditor
      .getByRole("searchbox", { name: "Find a Location" })
      .fill("Shared Pine");
    await vehicleEditor
      .getByRole("button", { name: "Search", exact: true })
      .click();
    await vehicleEditor
      .getByRole("button", { name: /Shared Pine Street/ })
      .click();
    await vehicleEditor
      .getByRole("img", { name: "Map showing Shared Pine Street" })
      .scrollIntoViewIfNeeded();
    await page.setViewportSize({ width: 390, height: 844 });
    expect(
      await vehicleEditor.evaluate(
        (element) => element.scrollWidth <= element.clientWidth + 1,
      ),
    ).toBe(true);
    await page.screenshot({
      animations: "disabled",
      caret: "hide",
      path: "/private/tmp/memotrail-vehicle-location-form-mobile.png",
    });
    await vehicleEditor.getByRole("button", { name: "Add Vehicle" }).click();
    await expect(vehicleEditor).not.toBeVisible();

    const entries = (
      await client
        .from("entries")
        .select("id,title")
        .in("title", ["First hike", "Blue Civic"])
    ).data!;
    expect(entries).toHaveLength(2);
    const firstTimeId = entries.find(
      (entry) => entry.title === "First hike",
    )!.id;
    const vehicleId = entries.find((entry) => entry.title === "Blue Civic")!.id;
    const sharedLinks = (
      await client
        .from("entry_places")
        .select("entry_id,place_id")
        .in("entry_id", [firstTimeId, vehicleId])
        .eq("relationship", "primary")
    ).data!;
    expect(sharedLinks).toEqual(
      expect.arrayContaining([
        { entry_id: firstTimeId, place_id: locationId },
        { entry_id: vehicleId, place_id: locationId },
      ]),
    );

    await page.goto("/first-times");
    await page.getByRole("button", { name: /First hike/ }).click();
    const editDialog = page.getByRole("dialog");
    await expect(
      editDialog.getByRole("img", { name: "Map showing Shared Pine Street" }),
    ).toBeVisible();
    await editDialog.getByRole("button", { name: "Remove" }).click();
    await editDialog.getByRole("button", { name: "Save changes" }).click();
    await expect(editDialog).not.toBeVisible();
    const remaining = (
      await client
        .from("entry_places")
        .select("entry_id,place_id")
        .in("entry_id", [firstTimeId, vehicleId])
        .eq("relationship", "primary")
    ).data!;
    expect(remaining).toEqual([{ entry_id: vehicleId, place_id: locationId }]);
    expect(errors).toEqual([]);
  } finally {
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
