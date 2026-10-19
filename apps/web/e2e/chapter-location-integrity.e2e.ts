import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

test("Chapter keeps Location optional, keeps its own snapshot, and refuses a stale edit", async ({
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
  const email = `chapter-location-${randomUUID()}@memotrail.local`;
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
              providerLocationId: "synthetic-chapter-address",
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

    async function addChapter(title: string) {
      await page.goto("/timeline");
      await page
        .getByRole("button", { name: "Add to Timeline" })
        .first()
        .click();
      await page
        .getByRole("dialog", { name: "What are you adding?" })
        .getByRole("button", { name: "Add Chapter" })
        .click();
      const dialog = page.getByRole("dialog", { name: "Add a Chapter" });
      await dialog
        .getByRole("textbox", { name: "Title", exact: true })
        .fill(title);
      return dialog;
    }
    const entryId = async (title: string) =>
      (
        await client
          .from("entries")
          .select("id")
          .eq("owner_id", owner)
          .eq("title", title)
          .single()
      ).data!.id as string;

    const emptyChapter = await addChapter("Chapter without coordinates");
    await emptyChapter
      .getByRole("button", { name: "Add", exact: true })
      .click();
    await expect(emptyChapter).not.toBeVisible();
    expect(
      (
        await client
          .from("entry_locations")
          .select("location_id")
          .eq("entry_id", await entryId("Chapter without coordinates"))
      ).data,
    ).toEqual([]);

    const mappedChapter = await addChapter("Mapped Pine Chapter");
    await mappedChapter
      .getByRole("combobox", { name: "Find a Location" })
      .fill("Pine Street");
    await mappedChapter.getByRole("option", { name: /10 Pine Street/ }).click();
    await mappedChapter
      .getByRole("button", { name: "Add", exact: true })
      .click();
    await expect(mappedChapter).not.toBeVisible();
    const mappedId = await entryId("Mapped Pine Chapter");
    expect(
      (
        await client
          .from("locations")
          .select("address,latitude,longitude")
          .eq("owner_id", owner)
          .eq("bound_entry_id", mappedId)
          .single()
      ).data,
    ).toMatchObject({ address: "10 Pine Street", latitude: 39.952612 });

    // Choosing a Location again on its own page saves like any other edit.
    await page.goto(`/items/${mappedId}`);
    await expect(
      page.getByRole("heading", { name: "Mapped Pine Chapter" }),
    ).toBeVisible();
    const editChapter = page.getByRole("button", { name: "Edit Chapter" });
    await editChapter.click();
    const providerEdit = page.getByRole("dialog", { name: "Edit Entry" });
    await providerEdit
      .getByRole("combobox", { name: "Change Location" })
      .fill("Pine Street");
    await providerEdit.getByRole("option", { name: /10 Pine Street/ }).click();
    await providerEdit.getByRole("button", { name: "Save changes" }).click();
    await expect(providerEdit).not.toBeVisible();

    // An edit made from a stale copy is refused where the person is working.
    const mappedEntry = (
      await admin
        .from("entries")
        .select("id,revision")
        .eq("id", mappedId)
        .single()
    ).data!;
    await editChapter.click();
    const staleEdit = page.getByRole("dialog", { name: "Edit Entry" });
    // The editor loads the latest copy first, so wait for it before another device writes.
    await expect(staleEdit).toBeVisible();
    expect(
      (
        await admin
          .from("entries")
          .update({ revision: mappedEntry.revision + 1 })
          .eq("id", mappedEntry.id)
      ).error,
    ).toBeNull();
    await staleEdit
      .getByRole("textbox", { name: "Title", exact: true })
      .fill("Stale edit");
    await staleEdit.getByRole("button", { name: "Save changes" }).click();
    await expect(staleEdit.getByRole("alert")).toContainText(
      "changed on another device",
    );
    await staleEdit.screenshot({
      path: test.info().outputPath("memotrail-chapter-save-error.png"),
    });
    await staleEdit.getByRole("button", { name: "Cancel" }).click();
  } finally {
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
