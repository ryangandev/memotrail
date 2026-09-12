import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

for (const kind of ["first_time", "home", "vehicle", "goal"] as const) {
  test(`${kind} editing preserves trashed Collection membership`, async ({
    page,
    context,
  }) => {
    const uiErrors: string[] = [];
    page.on("pageerror", (error) => uiErrors.push(error.message));
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
    const email = `archived-membership-${randomUUID()}@memotrail.local`;
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
              ...values.map((v) => ({ name: v.name, value: v.value })),
            );
          },
        },
      });
      const link = await admin.auth.admin.generateLink({
        type: "magiclink",
        email,
      });
      await client.auth.verifyOtp({
        type: "magiclink",
        token_hash: link.data.properties!.hashed_token,
      });
      await context.addCookies(
        cookies.map((c) => ({
          ...c,
          domain: "127.0.0.1",
          path: "/",
          sameSite: "Lax",
          httpOnly: false,
        })),
      );

      const common = {
        p_title: "Archived membership fixture",
        p_body: "Original writing",
        p_collection_names: ["Recoverable memories", "Visible memories"],
        p_tag_names: [],
        p_entry_id: null,
        p_expected_revision: null,
      };
      const dates = {
        p_occurred_start: "2017-07-08T12:00:00Z",
        p_occurred_end: null,
        p_date_precision: "day",
        p_occurred_label: null,
        p_occurred_timezone: "UTC",
      };
      const configs = {
        first_time: {
          rpc: "save_first_time_with_occurrence",
          path: "/first-times",
          args: { ...common, ...dates },
        },
        home: {
          rpc: "save_home_entry",
          path: "/homes",
          args: {
            ...common,
            ...dates,
            p_place_id: null,
            p_place_name: "Test home",
            p_address: null,
            p_city: null,
            p_region: null,
            p_country: null,
            p_latitude: null,
            p_longitude: null,
            p_place_notes: "",
            p_move_in_reason: "",
            p_move_out_reason: "",
          },
        },
        vehicle: {
          rpc: "save_vehicle_entry",
          path: "/vehicles",
          args: {
            ...common,
            ...dates,
            p_make: "Test",
            p_model: "Car",
            p_model_year: null,
            p_color: "",
          },
        },
        goal: {
          rpc: "save_goal_entry",
          path: "/goals",
          args: {
            ...common,
            p_horizon: "someday",
            p_status: "active",
            p_target_date: null,
            p_related_entry_ids: [],
          },
        },
      };
      const config = configs[kind];
      const saved = await client.rpc(config.rpc, config.args);
      expect(saved.error).toBeNull();
      const id = saved.data[0].entry_id;
      const collection = (
        await client
          .from("collections")
          .select("id,revision")
          .eq("name", "Recoverable memories")
          .single()
      ).data!;
      expect(
        (
          await client.rpc("trash_collection", {
            p_id: collection.id,
            p_expected_revision: collection.revision,
          })
        ).error,
      ).toBeNull();
      await page.goto(config.path);
      await page
        .getByRole("button", { name: /Archived membership fixture/ })
        .click();
      const dialog = page.getByRole("dialog");
      await expect(dialog).not.toContainText("Recoverable memories");
      await dialog
        .getByRole("button", { name: "Save changes", exact: true })
        .click();
      await expect(dialog).not.toBeVisible();
      expect(
        (
          await client
            .from("entry_collections")
            .select("collection_id")
            .eq("entry_id", id)
            .eq("collection_id", collection.id)
        ).data,
      ).toHaveLength(1);
      expect(
        (
          await client
            .from("collections")
            .select("id")
            .eq("name", "Recoverable memories")
        ).data,
      ).toHaveLength(1);
      // The same authenticated RPC is the native client's mutation boundary.
      const revision = (
        await client.from("entries").select("revision").eq("id", id).single()
      ).data!.revision;
      const native = await client.rpc(config.rpc, {
        ...config.args,
        p_entry_id: id,
        p_expected_revision: revision,
        p_collection_names: [],
      });
      expect(native.error).toBeNull();
      const memberships = (
        await client
          .from("entry_collections")
          .select("collection_id")
          .eq("entry_id", id)
      ).data;
      expect(memberships).toEqual([{ collection_id: collection.id }]);
      await page.goto("/trash");
      await page.getByRole("button", { name: "Restore", exact: true }).click();
      await expect(
        page.getByText("Recoverable memories", { exact: true }),
      ).not.toBeVisible();
      await page.goto("/collections/" + collection.id);
      await expect(
        page.getByText("Archived membership fixture", { exact: true }),
      ).toBeVisible();
      expect(uiErrors).toEqual([]);
    } finally {
      await admin.auth.admin.deleteUser(owner);
    }
  });
}
