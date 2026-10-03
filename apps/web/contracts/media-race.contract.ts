import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import sharp from "sharp";
import { query, transaction } from "./helpers/local-sql";

for (const first of ["deletion", "generation"] as const) {
  test(`Concurrent media cleanup is safe when ${first} locks first`, async () => {
    const env = JSON.parse(
      execFileSync("supabase", ["status", "-o", "json"], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }),
    );
    expect(env.API_URL).toBe("http://127.0.0.1:54321");
    const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY);
    const email = `media-race-${randomUUID()}@memotrail.local`;
    const user = await admin.auth.admin.createUser({
      email,
      email_confirm: true,
    });
    const owner = user.data.user!.id,
      entry = randomUUID(),
      original = randomUUID();
    const label = `media-race-${owner}`;
    const path = `${owner}/${entry}/${original}.png`;
    const derived = `${owner}/${entry}/derived/${original}/v1/${"b".repeat(64)}/display.webp`;
    const tx = transaction();
    try {
      const client = createClient(env.API_URL, env.ANON_KEY, {
        auth: { persistSession: false },
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
      expect(
        (
          await client
            .from("entries")
            .insert({ id: entry, owner_id: owner, title: "Concurrent cleanup" })
        ).error,
      ).toBeNull();
      const bytes = await sharp({
        create: { width: 16, height: 16, channels: 3, background: "#316652" },
      })
        .png()
        .toBuffer();
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
            p_entry_id: entry,
            p_attachment_id: original,
            p_object_path: path,
            p_original_filename: "race.png",
            p_mime_type: "image/png",
            p_byte_size: bytes.length,
            p_pixel_width: 16,
            p_pixel_height: 16,
          })
        ).error,
      ).toBeNull();
      expect(
        (
          await client.rpc("trash_entry_attachment", {
            p_attachment_id: original,
          })
        ).error,
      ).toBeNull();
      const row = await client
        .from("attachments")
        .select("deleted_at")
        .eq("id", original)
        .single();
      const params = {
        p_item_kind: "attachment",
        p_item_id: original,
        p_expected_revision: null,
        p_expected_deleted_at: row.data!.deleted_at,
      };
      await tx.run(`set application_name='${label}'; begin;`);
      if (first === "deletion") {
        await tx.run(`delete from public.attachments where id='${original}';`);
        const upload = Promise.resolve(
          admin.storage
            .from("entry-media")
            .upload(derived, await sharp(bytes).webp().toBuffer(), {
              contentType: "image/webp",
            }),
        );
        await expect
          .poll(() =>
            query(
              `select count(*) from pg_stat_activity a where (select pid from pg_stat_activity where application_name='${label}')=any(pg_blocking_pids(a.pid))`,
            ),
          )
          .toBe("1");
        await tx.run("commit;");
        expect((await upload).error).not.toBeNull();
        expect(
          query(
            `select count(*) from storage.objects where bucket_id='entry-media' and name='${derived}'`,
          ),
        ).toBe("0");
      } else {
        // Hold the same Storage transaction/parent key-share lock used by a real upload.
        await tx.run(
          `insert into storage.objects(bucket_id,name) values('entry-media','${derived}');`,
        );
        const removal = Promise.resolve(
          client.rpc("delete_trash_item_forever", params),
        );
        await expect
          .poll(() =>
            query(
              `select count(*) from pg_stat_activity a where (select pid from pg_stat_activity where application_name='${label}')=any(pg_blocking_pids(a.pid))`,
            ),
          )
          .toBe("1");
        await tx.run("commit;");
        expect((await removal).error?.message).toBe("media_cleanup_required");
        const manifest = await client.rpc("trash_item_storage_paths", params);
        expect(manifest.error).toBeNull();
        expect(
          manifest.data.map((v: { object_path: string }) => v.object_path),
        ).toContain(derived);
        expect(
          (
            await client.storage
              .from("entry-media")
              .remove(
                manifest.data.map(
                  (v: { object_path: string }) => v.object_path,
                ),
              )
          ).error,
        ).toBeNull();
        expect(
          (await client.rpc("delete_trash_item_forever", params)).error,
        ).toBeNull();
      }
      expect(
        (await client.from("attachments").select("id").eq("id", original)).data,
      ).toEqual([]);
    } finally {
      await tx.close();
      const paths = query(
        `select name from storage.objects where bucket_id='entry-media' and split_part(name,'/',1)='${owner}'`,
      )
        .split("\n")
        .filter(Boolean);
      if (paths.length)
        expect(
          (await admin.storage.from("entry-media").remove(paths)).error,
        ).toBeNull();
      expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
    }
  });
}
