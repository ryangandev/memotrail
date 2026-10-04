import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import sharp from "sharp";
import { query, transaction } from "./helpers/local-sql";

// Photo changes leave the Entry's revision alone, so Move to Trash waiting
// behind a photo removal still succeeds, while waiting behind writing conflicts.
for (const concurrent of ["photo removal", "writing"] as const) {
  test(`Goal Trash waiting behind concurrent ${concurrent} ${concurrent === "writing" ? "conflicts" : "succeeds"}`, async () => {
    const env = JSON.parse(
      execFileSync("supabase", ["status", "-o", "json"], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }),
    );
    expect(env.API_URL).toBe("http://127.0.0.1:54321");
    const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY);
    const email = `goal-trash-race-${randomUUID()}@memotrail.local`;
    const user = await admin.auth.admin.createUser({
      email,
      email_confirm: true,
    });
    expect(user.error).toBeNull();
    const owner = user.data.user!.id,
      photo = randomUUID();
    const label = `goal-trash-race-${owner}`;
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
      const saved = await client.rpc("save_goal_entry", {
        p_title: "Concurrent Trash",
        p_body: "Original writing",
        p_status: "active",
        p_target_date: null,
        p_tag_names: [],
        p_entry_id: null,
        p_expected_revision: null,
      });
      expect(saved.error).toBeNull();
      const entry: string = saved.data[0].entry_id;
      const path = `${owner}/${entry}/${photo}.png`;
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
            p_attachment_id: photo,
            p_object_path: path,
            p_original_filename: "race.png",
            p_mime_type: "image/png",
            p_byte_size: bytes.length,
            p_pixel_width: 16,
            p_pixel_height: 16,
          })
        ).error,
      ).toBeNull();
      // The editor opens here, with the photo attached.
      const opened = 1;
      expect(
        query(`select revision from public.entries where id='${entry}'`),
      ).toBe(String(opened));

      await tx.run(
        `set application_name='${label}'; begin; set local role authenticated; select set_config('request.jwt.claims','{"sub":"${owner}","role":"authenticated"}',true);`,
      );
      await tx.run(
        concurrent === "photo removal"
          ? `select count(*) from public.trash_entry_attachment('${photo}');`
          : `update public.entries set body='Other device writing' where id='${entry}';`,
      );
      const trash = Promise.resolve(
        client.rpc("trash_goal_entry", {
          p_entry_id: entry,
          p_expected_revision: opened,
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

      const trashed = await trash;
      expect(trashed.error).toBeNull();
      const row = await client
        .from("entries")
        .select("body,deleted_at,revision")
        .eq("id", entry)
        .single();
      expect(row.error).toBeNull();
      if (concurrent === "photo removal") {
        expect(trashed.data).toEqual([{ entry_id: entry, revision: 2 }]);
        expect(row.data!.deleted_at).not.toBeNull();
      } else {
        expect(trashed.data).toEqual([]);
        expect(row.data).toEqual({
          body: "Other device writing",
          deleted_at: null,
          revision: 2,
        });
      }
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
