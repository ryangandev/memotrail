import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
test("History restores and re-restores writing, relationships, and private photo membership with conflict protection", async ({
  page,
  context,
}) => {
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
  const email = `history-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  if (!created.data.user) throw new Error("Local history fixture unavailable.");
  const ownerID = created.data.user.id,
    entryID = randomUUID(),
    photoID = randomUUID(),
    tagID = randomUUID();
  const path = `${ownerID}/${entryID}/${photoID}.png`;
  const bytes = Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=",
    "base64",
  );
  try {
    const cookies: { name: string; value: string }[] = [];
    const client = createServerClient(env.API_URL, env.ANON_KEY, {
      cookies: {
        getAll: () => cookies,
        setAll: (values) => {
          cookies.push(
            ...values.map((v) => ({ name: v.name, value: v.value })),
          );
        },
      },
    });
    const link = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    if (!link.data.properties) throw new Error("Local sign-in unavailable.");
    expect(
      (
        await client.auth.verifyOtp({
          type: "magiclink",
          token_hash: link.data.properties.hashed_token,
        })
      ).error,
    ).toBeNull();
    await context.addCookies(
      cookies.map((c) => ({
        ...c,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax" as const,
        httpOnly: false,
      })),
    );
    expect(
      (
        await client.from("entries").insert({
          id: entryID,
          owner_id: ownerID,
          title: "Original chapter",
          body: "The original words I want to keep.",
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("tags").insert({
          id: tagID,
          owner_id: ownerID,
          name: "Original tag",
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("entry_tags").insert({
          entry_id: entryID,
          tag_id: tagID,
          owner_id: ownerID,
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.storage
          .from("entry-media")
          .upload(path, bytes, { contentType: "image/png" })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.rpc("register_entry_attachment", {
          p_entry_id: entryID,
          p_attachment_id: photoID,
          p_object_path: path,
          p_original_filename: "memory.png",
          p_mime_type: "image/png",
          p_byte_size: bytes.length,
          p_pixel_width: 1,
          p_pixel_height: 1,
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.rpc("review_wiki_item_with_location_rich", {
          p_entry_id: entryID,
          p_expected_revision: 2,
          p_title: "Revised chapter",
          p_body: "The newer words before restoration.",
          p_item_kind: "entry",
          p_item_subtype: "entry",
          p_occurred_start: "2024-01-01T12:00:00Z",
          p_occurred_timezone: "UTC",
          p_tag_names: [],
          p_occurred_end: null,
          p_occurred_label: null,
          p_date_precision: "day",
          p_photo_place: null,
          p_primary_location: null,
          p_body_rich: null,
        })
      ).error,
    ).toBeNull();
    const errors: string[] = [];
    page.on("pageerror", (e) => errors.push(e.message));
    await page.goto("/history");
    // One page of results needs no pager.
    await expect(
      page.getByRole("navigation", { name: "History pages" }),
    ).toHaveCount(0);
    await page.getByRole("link", { name: /Revised chapter/ }).click();
    const earlier = page.getByRole("region", { name: "Earlier version" }),
      current = page.getByRole("region", { name: "Current version" });
    await expect(earlier).toContainText("The original words I want to keep.");
    await expect(earlier).toContainText("Original tag");
    await expect(earlier).toContainText("memory.png");
    await expect(current).toContainText("The newer words before restoration.");
    await expect(
      page.getByRole("navigation", { name: "Version pages" }),
    ).toHaveCount(0);
    // Every recorded version uses the current snapshot schema, so none is flagged as early.
    await expect(page.getByText("This early snapshot")).toHaveCount(0);
    await page.screenshot({
      path: "/private/tmp/memotrail-history-desktop.png",
      fullPage: true,
      caret: "initial",
    });
    await page
      .getByRole("button", { name: "Restore selected version" })
      .click();
    await page
      .getByRole("dialog", { name: /Restore version \d+\?/ })
      .getByRole("button", { name: "Restore version", exact: true })
      .click();
    await expect(current).toContainText("Current · version 4");
    await expect(current).toContainText("The original words I want to keep.");
    const restored = await client
      .from("entry_tags")
      .select("tag_id")
      .eq("entry_id", entryID);
    expect(restored.data?.[0]?.tag_id).toBe(tagID);
    await page
      .getByRole("button", { name: "Restore selected version" })
      .click();
    await page
      .getByRole("dialog", { name: /Restore version \d+\?/ })
      .getByRole("button", { name: "Restore version", exact: true })
      .click();
    await expect(current).toContainText("Current · version 5");
    await expect(current).toContainText("The newer words before restoration.");
    expect(
      (
        await client
          .from("entries")
          .update({ body: "Another device updated this Entry." })
          .eq("id", entryID)
      ).error,
    ).toBeNull();
    await page
      .getByRole("button", { name: "Restore selected version" })
      .click();
    await page
      .getByRole("dialog", { name: /Restore version \d+\?/ })
      .getByRole("button", { name: "Restore version", exact: true })
      .click();
    await expect(
      page.getByRole("alert").filter({ hasText: "changed on another device" }),
    ).toContainText("changed on another device");
    const fresh = await client
      .from("entries")
      .select("revision,body")
      .eq("id", entryID)
      .single();
    expect(fresh.data?.revision).toBe(6);
    expect(fresh.data?.body).toBe("Another device updated this Entry.");
    const downloaded = await client.storage.from("entry-media").download(path);
    expect(downloaded.error).toBeNull();
    expect(Buffer.from(await downloaded.data!.arrayBuffer())).toEqual(bytes);
    await page.reload();
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await expect(current).toContainText("Current · version 6");
    await page.screenshot({
      path: "/private/tmp/memotrail-history-mobile.png",
      fullPage: true,
      caret: "initial",
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);
    expect(errors).toEqual([]);
  } finally {
    const removed = await admin.storage.from("entry-media").remove([path]);
    const deleted = await admin.auth.admin.deleteUser(ownerID);
    if (removed.error || deleted.error)
      throw new Error("Could not clean up isolated history fixtures.");
  }
});

const focusedHistoryTest = test.extend<{
  historyFixture: { client: SupabaseClient; admin: SupabaseClient };
}>({
  historyFixture: async ({ context }, provideFixture) => {
    const local = JSON.parse(
      execFileSync("supabase", ["status", "-o", "json"], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }),
    );
    expect(local.API_URL).toBe("http://127.0.0.1:54321");
    const admin = createClient(local.API_URL, local.SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });
    const email = `focused-history-${randomUUID()}@memotrail.local`;
    const created = await admin.auth.admin.createUser({
      email,
      email_confirm: true,
    });
    expect(created.error).toBeNull();
    const owner = created.data.user!.id;
    try {
      const cookies: { name: string; value: string }[] = [];
      const client = createServerClient(local.API_URL, local.ANON_KEY, {
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
      expect(link.error).toBeNull();
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
          path: "/",
          sameSite: "Lax" as const,
        })),
      );
      await provideFixture({ client, admin });
    } finally {
      expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
    }
  },
});

for (const schema of [3, 2, undefined]) {
  focusedHistoryTest(
    `Home history handles ${schema === undefined ? "missing" : `schema ${schema}`} history format before restoration`,
    async ({ page, historyFixture }) => {
      const { client, admin } = historyFixture;
      const saved = await client.rpc("save_home_entry_with_occurrence", {
        p_entry_id: null,
        p_expected_revision: null,
        p_title: "Original home name",
        p_body: "My first home.",
        p_occurred_start: null,
        p_occurred_end: null,
        p_date_precision: "unknown",
        p_occurred_label: null,
        p_occurred_timezone: "UTC",
        p_tag_names: [],
        p_place_id: null,
        p_place_name: null,
        p_address: null,
        p_city: null,
        p_region: null,
        p_country: null,
        p_latitude: null,
        p_longitude: null,
        p_place_notes: null,
        p_move_in_reason: null,
        p_move_out_reason: null,
      });
      expect(saved.error).toBeNull();
      const entryID = saved.data![0].entry_id as string;
      const errors: string[] = [];
      page.on("pageerror", (error) => errors.push(error.message));
      await page.goto(`/homes/${entryID}`);
      await page.getByRole("button", { name: "Edit Home" }).click();
      await page
        .getByRole("textbox", { name: "Home name", exact: true })
        .fill("Renamed home");
      await page
        .getByRole("button", { name: "Save changes", exact: true })
        .click();
      await expect(
        page.getByRole("button", { name: "Edit Home" }),
      ).toBeVisible();
      const version = await admin
        .from("entry_versions")
        .select("snapshot")
        .eq("entry_id", entryID)
        .eq("version", 1)
        .single();
      expect(version.error).toBeNull();
      expect(version.data!.snapshot.history_schema).toBe(3);
      if (schema !== 3) {
        // Keep a supported newer version alongside the stored legacy version.
        expect(
          (
            await client
              .from("entries")
              .update({ title: "Current home name" })
              .eq("id", entryID)
          ).error,
        ).toBeNull();
        const snapshot = version.data!.snapshot;
        if (schema === undefined) delete snapshot.history_schema;
        else snapshot.history_schema = schema;
        expect(
          (
            await admin
              .from("entry_versions")
              .update({ snapshot })
              .eq("entry_id", entryID)
              .eq("version", 1)
          ).error,
        ).toBeNull();
        const rejected = await client.rpc("restore_entry_version", {
          p_entry_id: entryID,
          p_version: 1,
          p_expected_revision: 3,
        });
        expect(rejected.error?.message).toBe("history_schema_unsupported");
      }
      await page.goto(`/history?entry=${entryID}`);
      const restore = page.getByRole("button", {
        name: "Restore selected version",
        exact: true,
      });
      const unavailable = page.getByText(
        "This version was saved in a format that cannot be restored. You can still review its recorded content.",
        { exact: true },
      );
      if (schema !== 3) {
        await expect(restore).toBeEnabled();
        await expect(unavailable).not.toBeVisible();
        await page
          .getByRole("combobox", { name: "Earlier version" })
          .selectOption("1");
        await expect(restore).toBeDisabled();
        await expect(unavailable).toBeVisible();
        await expect(restore).toHaveAccessibleDescription(
          await unavailable.innerText(),
        );
        await expect(page.getByRole("dialog")).not.toBeVisible();
        await expect(page.locator('p[role="alert"]')).not.toBeVisible();
        await expect(
          page.getByText(
            "This early snapshot has incomplete relationship history.",
            { exact: false },
          ),
        ).not.toBeVisible();
        await page.screenshot({
          path: `/private/tmp/history-schema-${schema ?? "missing"}-after.png`,
          fullPage: true,
          caret: "initial",
        });
        await expect(
          page.getByRole("region", { name: "Earlier version", exact: true }),
        ).toContainText("Original home name");
        await page
          .getByRole("combobox", { name: "Earlier version" })
          .selectOption("2");
        await expect(restore).toBeEnabled();
        await expect(unavailable).not.toBeVisible();
        const current = await client
          .from("entries")
          .select("title,revision")
          .eq("id", entryID)
          .single();
        expect(current.data).toEqual({
          title: "Current home name",
          revision: 3,
        });
      } else {
        await expect(restore).toBeEnabled();
        await page.screenshot({
          path: "/private/tmp/history-schema-3-after.png",
          fullPage: true,
          caret: "initial",
        });
        await expect(
          page.getByText(
            "This early snapshot has incomplete relationship history.",
            { exact: false },
          ),
        ).not.toBeVisible();
        await expect(unavailable).not.toBeVisible();
        await restore.click();
        await page
          .getByRole("button", { name: "Restore version", exact: true })
          .click();
        await expect(
          page.getByRole("region", { name: "Current version", exact: true }),
        ).toContainText("Current · version 3");
        const current = await client
          .from("entries")
          .select("title,revision")
          .eq("id", entryID)
          .single();
        expect(current.data).toEqual({
          title: "Original home name",
          revision: 3,
        });
      }
      expect(errors).toEqual([]);
    },
  );
}

const focusedCases = [
  {
    kind: "Home",
    field: "Why you moved in",
    value: "Closer to work",
    differences: "Home details",
  },
  {
    kind: "Home",
    field: "Home name",
    value: "Maple Street home",
    differences: "Title",
  },
  {
    kind: "Vehicle",
    field: "Color",
    value: "Red",
    differences: "Vehicle details",
  },
  {
    kind: "Vehicle",
    field: "Name or nickname",
    value: "Road trip car",
    differences: "Title",
  },
  {
    kind: "Home",
    field: "Why you moved in",
    value: "Closer to work",
    differences: "Home details",
    legacy: true,
  },
] as const;

for (const scenario of focusedCases) {
  focusedHistoryTest(
    `${scenario.kind} history compares only ${scenario.differences}${"legacy" in scenario ? " in a legacy snapshot" : ""}`,
    async ({ page, historyFixture }) => {
      const { client, admin } = historyFixture;
      const common = {
        p_entry_id: null,
        p_expected_revision: null,
        p_title: scenario.kind === "Home" ? "Maple Street flat" : "Blue Civic",
        p_body: "A chapter to remember.",
        p_occurred_start: "2021-04-12T12:00:00Z",
        p_occurred_end: null,
        p_date_precision: "day",
        p_occurred_label: null,
        p_occurred_timezone: "UTC",
        p_tag_names: [],
      };
      const saved =
        scenario.kind === "Home"
          ? await client.rpc("save_home_entry_with_occurrence", {
              ...common,
              p_place_id: null,
              p_place_name: "Maple Street",
              p_address: "10 Maple Street",
              p_city: "Philadelphia",
              p_region: "Pennsylvania",
              p_country: "United States",
              p_latitude: 39.95,
              p_longitude: -75.16,
              p_place_notes: null,
              p_move_in_reason: "Study",
              p_move_out_reason: null,
            })
          : await client.rpc("save_vehicle_entry_with_occurrence", {
              ...common,
              p_make: "Honda",
              p_model: "Civic",
              p_model_year: 2018,
              p_color: "Blue",
            });
      expect(saved.error).toBeNull();
      const entryID = saved.data![0].entry_id as string;
      const errors: string[] = [];
      page.on("pageerror", (error) => errors.push(error.message));
      await page.goto(
        `/${scenario.kind === "Home" ? "homes" : "vehicles"}/${entryID}`,
      );
      await page.getByRole("button", { name: `Edit ${scenario.kind}` }).click();
      await page
        .getByRole("textbox", { name: scenario.field, exact: true })
        .fill(scenario.value);
      await page
        .getByRole("button", { name: "Save changes", exact: true })
        .click();
      await expect(
        page.getByRole("button", { name: `Edit ${scenario.kind}` }),
      ).toBeVisible();
      if ("legacy" in scenario) {
        // Simulate a stored pre-migration snapshot without rewriting it on read.
        const version = await admin
          .from("entry_versions")
          .select("snapshot")
          .eq("entry_id", entryID)
          .eq("version", 1)
          .single();
        expect(version.error).toBeNull();
        const snapshot = version.data!.snapshot;
        for (const key of [
          "places",
          "timeline_items",
          "links",
          "attachments",
        ]) {
          snapshot[key] = snapshot[key].map((row: Record<string, unknown>) => ({
            ...row,
            created_at: "2000-01-01T00:00:00Z",
            updated_at: "2000-01-01T00:00:00Z",
          }));
        }
        snapshot.home = {
          ...snapshot.home,
          created_at: "2000-01-01T00:00:00Z",
          updated_at: "2000-01-01T00:00:00Z",
        };
        expect(
          (
            await admin
              .from("entry_versions")
              .update({ snapshot })
              .eq("entry_id", entryID)
              .eq("version", 1)
          ).error,
        ).toBeNull();
      }
      await page.goto(`/history?entry=${entryID}`);
      const notice = page
        .locator("p")
        .filter({ hasText: "Differences from current version:" });
      await expect(notice).toBeVisible();
      await page.screenshot({
        path: `/private/tmp/history-${scenario.kind.toLowerCase()}-${scenario.differences.toLowerCase().replaceAll(" ", "-")}${"legacy" in scenario ? "-legacy" : ""}.png`,
        fullPage: true,
        caret: "initial",
      });
      await expect(notice).toHaveText(
        `Differences from current version: ${scenario.differences}. Your current version 2 will stay in history.`,
      );
      expect(errors).toEqual([]);
    },
  );
}
