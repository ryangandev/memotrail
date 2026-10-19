import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

test("First Time and Chapter keep separate snapshots of one address", async ({
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
              providerLocationId: "pine-street-provider-id",
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

    await page.goto("/first-times");
    await page.getByRole("button", { name: "Add First Time" }).first().click();
    const firstTimeEditor = page.getByRole("dialog", {
      name: "Add a First Time",
    });
    await firstTimeEditor
      .getByRole("textbox", { name: "Title" })
      .fill("First hike");
    await firstTimeEditor
      .getByRole("combobox", { name: "Find a Location" })
      .fill("10 Pine");
    await firstTimeEditor
      .getByRole("button", { name: "Search", exact: true })
      .click();
    await firstTimeEditor
      .getByRole("option", { name: /10 Pine Street/ })
      .click();
    await expect(
      firstTimeEditor.getByRole("img", {
        name: /Map showing 10 Pine Street/,
      }),
    ).toBeVisible();
    const firstTimeMap = firstTimeEditor.getByRole("img", {
      name: /Map showing 10 Pine Street/,
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
      path: test.info().outputPath("memotrail-first-time-location-form.png"),
    });
    await firstTimeEditor
      .getByRole("button", { name: "Add", exact: true })
      .click();
    await expect(firstTimeEditor).not.toBeVisible();
    const firstTimeCard = page.getByRole("button", { name: /First hike/ });
    await expect(
      firstTimeCard.locator('[data-record-card-map="true"]'),
    ).toBeVisible();
    await firstTimeCard.screenshot({
      path: test.info().outputPath("memotrail-first-time-map-card-desktop.png"),
    });

    await page.goto("/timeline");
    await page.getByRole("button", { name: "Add to Timeline" }).first().click();
    await page
      .getByRole("dialog", { name: "What are you adding?" })
      .getByRole("button", { name: "Add Chapter" })
      .click();
    const chapterEditor = page.getByRole("dialog", { name: "Add a Chapter" });
    await chapterEditor
      .getByRole("textbox", { name: "Title" })
      .fill("Blue Civic years");
    await chapterEditor
      .getByRole("combobox", { name: "Find a Location" })
      .fill("10 Pine");
    await chapterEditor
      .getByRole("button", { name: "Search", exact: true })
      .click();
    await chapterEditor.getByRole("option", { name: /10 Pine Street/ }).click();
    await chapterEditor
      .getByRole("img", { name: /Map showing 10 Pine Street/ })
      .scrollIntoViewIfNeeded();
    await page.setViewportSize({ width: 390, height: 844 });
    expect(
      await chapterEditor.evaluate(
        (element) => element.scrollWidth <= element.clientWidth + 1,
      ),
    ).toBe(true);
    await page.screenshot({
      animations: "disabled",
      caret: "hide",
      path: test
        .info()
        .outputPath("memotrail-chapter-location-form-mobile.png"),
    });
    await chapterEditor
      .getByRole("button", { name: "Add", exact: true })
      .click();
    await expect(chapterEditor).not.toBeVisible();

    const entries = (
      await client
        .from("entries")
        .select("id,title")
        .in("title", ["First hike", "Blue Civic years"])
    ).data!;
    expect(entries).toHaveLength(2);
    const firstTimeId = entries.find(
      (entry) => entry.title === "First hike",
    )!.id;
    const chapterId = entries.find(
      (entry) => entry.title === "Blue Civic years",
    )!.id;
    const links = (
      await client
        .from("entry_locations")
        .select("entry_id,location_id")
        .in("entry_id", [firstTimeId, chapterId])
        .eq("relationship", "primary")
    ).data!;
    expect(links).toHaveLength(2);
    expect(links[0].location_id).not.toBe(links[1].location_id);
    const firstTimeLocationId = links.find(
      (link) => link.entry_id === firstTimeId,
    )!.location_id;
    const chapterLocationId = links.find(
      (link) => link.entry_id === chapterId,
    )!.location_id;
    expect(
      (
        await client
          .from("locations")
          .select("provider_location_id,bound_entry_id")
          .in("id", [firstTimeLocationId, chapterLocationId])
      ).data,
    ).toEqual(
      expect.arrayContaining([
        {
          provider_location_id: "pine-street-provider-id",
          bound_entry_id: firstTimeId,
        },
        {
          provider_location_id: "pine-street-provider-id",
          bound_entry_id: chapterId,
        },
      ]),
    );

    await page.goto("/first-times");
    // The map appears after the client theme has mounted, before opening the editor.
    await expect(
      firstTimeCard.locator('[data-record-card-map="true"]'),
    ).toBeVisible();
    await firstTimeCard.click();
    await expect(page).toHaveURL(`/items/${firstTimeId}`);
    await page.getByRole("button", { name: "Edit Entry" }).click();
    const editDialog = page.getByRole("dialog", { name: "Edit Entry" });
    await expect(
      editDialog.getByRole("img", { name: /Map showing 10 Pine Street/ }),
    ).toBeVisible();
    await editDialog.getByRole("button", { name: "Remove" }).click();
    await editDialog.getByRole("button", { name: "Save changes" }).click();
    await expect(editDialog).not.toBeVisible();
    await page.goto("/first-times");
    await expect(
      page
        .getByRole("button", { name: /First hike/ })
        .locator('[data-record-card-map="true"]'),
    ).toHaveCount(0);
    const remaining = (
      await client
        .from("entry_locations")
        .select("entry_id,location_id")
        .in("entry_id", [firstTimeId, chapterId])
        .eq("relationship", "primary")
    ).data!;
    expect(remaining).toEqual([
      { entry_id: chapterId, location_id: chapterLocationId },
    ]);
    expect(errors).toEqual([]);
  } finally {
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
