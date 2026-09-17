import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import sharp from "sharp";
import { cleanupMediaFixture } from "./helpers/media-fixture";

for (const kind of ["first_time", "home", "vehicle", "goal"] as const) {
  for (const interrupted of [
    "registration",
    "upload",
    "concurrent writing",
  ] as const) {
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
        const previewCase =
          kind === "first_time" && interrupted === "registration";
        const selectedBytes = previewCase
          ? Buffer.from(
              readFileSync(
                "src/lib/media/fixtures/synthetic.heic.base64",
                "utf8",
              ).trim(),
              "base64",
            )
          : bytes;
        let dropped = false;
        await page.route(
          interrupted !== "upload"
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
            name: previewCase ? "retry.heic" : "retry.png",
            mimeType: previewCase ? "image/heic" : "image/png",
            buffer: selectedBytes,
          },
        ];
        if (interrupted !== "upload")
          selection.push({
            name: "second.png",
            mimeType: "image/png",
            buffer: bytes,
          });
        await dialog.locator('input[type="file"]').setInputFiles(selection);
        if (previewCase) {
          const preview = dialog.locator('img[alt="Selected retry.heic"]');
          await expect(preview).toBeVisible();
          await expect
            .poll(() =>
              preview.evaluate((image: HTMLImageElement) => image.naturalWidth),
            )
            .toBe(120);
          await expect(dialog.getByText("Photo unavailable")).toHaveCount(0);
          await page.route(
            "**/storage/v1/object/entry-media/**",
            async (route) => {
              await new Promise((resolve) => setTimeout(resolve, 300));
              await route.continue();
            },
          );
        }
        await dialog
          .getByRole("button", { name: "Save changes", exact: true })
          .click();
        if (previewCase) {
          await expect(
            dialog.getByRole("progressbar", {
              name: "Photo upload progress",
            }),
          ).toBeVisible();
        }
        await expect.poll(() => dropped).toBe(true);
        if (interrupted !== "upload") {
          await expect(
            dialog.getByRole("button", { name: "Save changes", exact: true }),
          ).toBeEnabled();
          if (interrupted === "concurrent writing") {
            expect(
              (
                await client
                  .from("entries")
                  .update({ body: "Other device writing" })
                  .eq("id", entry)
              ).error,
            ).toBeNull();
          }
          await dialog
            .getByRole("button", { name: "Save changes", exact: true })
            .click();
          if (interrupted === "concurrent writing") {
            await expect(
              dialog.getByText(/changed on another device/),
            ).toBeVisible();
            expect(
              (
                await client
                  .from("entries")
                  .select("body")
                  .eq("id", entry)
                  .single()
              ).data?.body,
            ).toBe("Other device writing");
            expect(
              (
                await client
                  .from("attachments")
                  .select("id")
                  .eq("entry_id", entry)
                  .eq("variant", "original")
              ).data,
            ).toHaveLength(2);
            return;
          }
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
            selection.find((item) =>
              photo.object_path.endsWith(
                item.mimeType === "image/heic" ? ".heic" : ".png",
              ),
            )?.buffer ?? bytes,
          );
        }
      } finally {
        await cleanupMediaFixture(admin, owner, env.API_URL);
      }
    });
  }
}
