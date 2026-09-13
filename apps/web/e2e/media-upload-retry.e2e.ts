import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import sharp from "sharp";
import { cleanupMediaFixture } from "./helpers/media-fixture";

for (const kind of ["first_time", "home", "vehicle", "goal"] as const) {
  for (const interrupted of ["registration", "upload"] as const) {
    test(`${kind} preserves original photo identities after a lost ${interrupted} response`, async ({
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
      const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY);
      const email = `media-upload-${randomUUID()}@memotrail.local`;
      const created = await admin.auth.admin.createUser({
        email,
        email_confirm: true,
      });
      expect(created.error).toBeNull();
      const owner = created.data.user!.id;
      try {
        const cookies: { name: string; value: string }[] = [];
        const client = createServerClient(env.API_URL, env.ANON_KEY, {
          cookies: {
            getAll: () => cookies,
            setAll: (values) => {
              cookies.push(
                ...values.map(({ name, value }) => ({ name, value })),
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
          })),
        );
        const common = {
          p_entry_id: null,
          p_expected_revision: null,
          p_title: "Upload retry fixture",
          p_body: "Original writing",
          p_collection_names: [],
          p_tag_names: [],
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
            path: "/first-times",
            rpc: "save_first_time_with_occurrence",
            args: { ...common, ...dates },
          },
          home: {
            path: "/homes",
            rpc: "save_home_entry",
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
            path: "/vehicles",
            rpc: "save_vehicle_entry",
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
            path: "/goals",
            rpc: "save_goal_entry",
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
        const entry = saved.data[0].entry_id;
        const bytes = await sharp({
          create: { width: 40, height: 24, channels: 3, background: "#316652" },
        })
          .png()
          .toBuffer();
        let dropped = false;
        await page.route(
          interrupted === "registration"
            ? `**${config.path}`
            : "**/storage/v1/object/entry-media/**",
          async (route) => {
            const request = route.request();
            if (
              !dropped &&
              request.method() === "POST" &&
              (interrupted === "upload" ||
                request.postData()?.includes('"attachmentId"'))
            ) {
              await route.fetch();
              dropped = true;
              await route.abort("failed");
            } else await route.continue();
          },
        );
        await page.goto(config.path);
        await page
          .getByRole("button", { name: /Upload retry fixture/ })
          .click();
        const dialog = page.getByRole("dialog");
        const selection = [
          {
            name: "retry.png",
            mimeType: "image/png",
            buffer: bytes,
          },
        ];
        if (interrupted === "registration")
          selection.push({
            name: "second.png",
            mimeType: "image/png",
            buffer: bytes,
          });
        await dialog.locator('input[type="file"]').setInputFiles(selection);
        await dialog
          .getByRole("button", { name: "Save changes", exact: true })
          .click();
        await expect.poll(() => dropped).toBe(true);
        if (interrupted === "registration") {
          await expect(
            dialog.getByRole("button", { name: "Save changes", exact: true }),
          ).toBeEnabled();
          await dialog
            .getByRole("button", { name: "Save changes", exact: true })
            .click();
        }
        await expect(dialog).not.toBeVisible();
        const photos = await client
          .from("attachments")
          .select("id,object_path")
          .eq("entry_id", entry)
          .eq("variant", "original")
          .is("deleted_at", null);
        expect(photos.error).toBeNull();
        expect(photos.data).toHaveLength(selection.length);
        for (const photo of photos.data!) {
          const original = await client.storage
            .from("entry-media")
            .download(photo.object_path);
          expect(original.error).toBeNull();
          expect(Buffer.from(await original.data!.arrayBuffer())).toEqual(
            bytes,
          );
        }
      } finally {
        await cleanupMediaFixture(admin, owner, env.API_URL);
      }
    });
  }
}
