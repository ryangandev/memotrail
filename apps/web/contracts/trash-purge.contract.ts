import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import sharp from "sharp";
import { finishMediaPurges } from "../src/lib/data/media-purge";
import { query, transaction } from "./helpers/local-sql";

type TrashParams = {
  p_item_kind: string;
  p_item_id: string;
  p_expected_revision: number | null;
  p_expected_deleted_at: string;
};

type Account = {
  admin: SupabaseClient;
  client: SupabaseClient;
  owner: string;
  photoEntry: (title: string) => Promise<{ entry: string; path: string }>;
  trashEntry: (entry: string) => Promise<TrashParams>;
  objectCount: (path: string) => string;
};

/** A disposable local account whose Storage objects and rows are removed afterwards. */
async function withAccount(run: (account: Account) => Promise<void>) {
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
  const email = `trash-purge-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  expect(created.error).toBeNull();
  const owner = created.data.user!.id;
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
    const bytes = await sharp({
      create: { width: 16, height: 16, channels: 3, background: "#316652" },
    })
      .png()
      .toBuffer();
    await run({
      admin,
      client,
      owner,
      async photoEntry(title) {
        const entry = randomUUID(),
          attachment = randomUUID();
        const path = `${owner}/${entry}/${attachment}.png`;
        expect(
          (
            await client
              .from("entries")
              .insert({ id: entry, owner_id: owner, title })
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
              p_entry_id: entry,
              p_attachment_id: attachment,
              p_object_path: path,
              p_original_filename: "purge.png",
              p_mime_type: "image/png",
              p_byte_size: bytes.length,
              p_pixel_width: 16,
              p_pixel_height: 16,
            })
          ).error,
        ).toBeNull();
        return { entry, path };
      },
      async trashEntry(entry) {
        expect(
          (
            await client
              .from("entries")
              .update({ deleted_at: new Date().toISOString() })
              .eq("id", entry)
          ).error,
        ).toBeNull();
        const row = await client
          .from("entries")
          .select("deleted_at,revision")
          .eq("id", entry)
          .single();
        expect(row.error).toBeNull();
        return {
          p_item_kind: "entry",
          p_item_id: entry,
          p_expected_revision: row.data!.revision,
          p_expected_deleted_at: row.data!.deleted_at,
        };
      },
      objectCount: (path) =>
        query(
          `select count(*) from storage.objects where bucket_id='entry-media' and name='${path}'`,
        ),
    });
  } finally {
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
}

const blockedBy = (label: string) =>
  query(
    `select count(*) from pg_stat_activity a where (select pid from pg_stat_activity where application_name='${label}')=any(pg_blocking_pids(a.pid))`,
  );

test("A deployed client's Delete forever sequence cannot lose a restorable original", async () => {
  await withAccount(async ({ client, photoEntry, trashEntry, objectCount }) => {
    const { entry, path } = await photoEntry("Old sequence");
    const params = await trashEntry(entry);
    const manifest = await client.rpc("trash_item_storage_paths", params);
    expect(manifest.error).toBeNull();
    expect(manifest.data).toEqual([]);
    // Even a client that removes the original by name before deleting keeps it.
    const early = await client.storage.from("entry-media").remove([path]);
    expect(early.error).toBeNull();
    expect(early.data).toEqual([]);
    expect(objectCount(path)).toBe("1");
    // Another device restores in the gap the old sequence left open.
    const restored = await client.rpc("restore_trash_item", params);
    expect(restored.error).toBeNull();
    expect(restored.data).toHaveLength(1);
    const stale = await client.rpc("delete_trash_item_forever", params);
    expect(stale.error).toBeNull();
    expect(stale.data).toEqual([]);
    expect(objectCount(path)).toBe("1");
    expect(
      (
        await client
          .from("entries")
          .select("deleted_at")
          .eq("id", entry)
          .single()
      ).data,
    ).toEqual({ deleted_at: null });
  });
});

test("An interrupted file removal after Delete forever is retried until complete", async () => {
  await withAccount(
    async ({ client, owner, photoEntry, trashEntry, objectCount }) => {
      const { entry, path } = await photoEntry("Interrupted removal");
      const params = await trashEntry(entry);
      const deleted = await client.rpc("delete_trash_item_forever", params);
      expect(deleted.error).toBeNull();
      expect(deleted.data).toHaveLength(1);
      // The response or the Storage request is lost here: nothing is restorable.
      const restore = await client.rpc("restore_trash_item", params);
      expect(restore.error).toBeNull();
      expect(restore.data).toEqual([]);
      expect(objectCount(path)).toBe("1");
      expect((await client.rpc("complete_media_purges")).data).toBe(1);
      const pending = await client.rpc("pending_media_purge_paths", {
        p_limit: 100,
      });
      expect(pending.data).toEqual([{ object_path: path }]);
      // The next attempt finishes the removal; another one is harmless.
      expect(await finishMediaPurges(client, owner)).toBe(true);
      expect(objectCount(path)).toBe("0");
      expect(await finishMediaPurges(client, owner)).toBe(true);
      expect(
        query(
          `select count(*) from public.media_purges where owner_id='${owner}'`,
        ),
      ).toBe("0");
    },
  );
});

test("Restore refuses an item whose original is missing, and Delete forever still works", async () => {
  await withAccount(
    async ({ admin, client, owner, photoEntry, trashEntry, objectCount }) => {
      const { entry, path } = await photoEntry("Missing original");
      const params = await trashEntry(entry);
      // Only a privileged path can remove a registered original.
      expect(
        (await admin.storage.from("entry-media").remove([path])).error,
      ).toBeNull();
      const restore = await client.rpc("restore_trash_item", params);
      expect(restore.error?.message).toBe("trash_media_unavailable");
      const direct = await client
        .from("entries")
        .update({ deleted_at: null })
        .eq("id", entry);
      expect(direct.error?.message).toBe("trash_media_unavailable");
      const deleted = await client.rpc("delete_trash_item_forever", params);
      expect(deleted.error).toBeNull();
      expect(deleted.data).toHaveLength(1);
      expect(await finishMediaPurges(client, owner)).toBe(true);
      expect(objectCount(path)).toBe("0");
    },
  );
});

for (const first of ["restore", "deletion"] as const) {
  test(`Restore and Delete forever serialize when ${first} locks first`, async () => {
    await withAccount(
      async ({ client, owner, photoEntry, trashEntry, objectCount }) => {
        const { entry, path } = await photoEntry(`Race ${first}`);
        const params = await trashEntry(entry);
        const label = `trash-purge-${owner}`;
        const tx = transaction();
        try {
          const call = (name: string) =>
            `select count(*) from public.${name}('entry','${entry}',${params.p_expected_revision},'${params.p_expected_deleted_at}');`;
          await tx.run(
            `set application_name='${label}'; begin; set local role authenticated; select set_config('request.jwt.claim.sub','${owner}',true);`,
          );
          if (first === "restore") {
            await tx.run(call("restore_trash_item"));
            const deletion = Promise.resolve(
              client.rpc("delete_trash_item_forever", params),
            );
            await expect.poll(() => blockedBy(label)).toBe("1");
            await tx.run("commit;");
            const result = await deletion;
            expect(result.error).toBeNull();
            expect(result.data).toEqual([]);
            expect(
              (
                await client
                  .from("entries")
                  .select("deleted_at")
                  .eq("id", entry)
                  .single()
              ).data,
            ).toEqual({ deleted_at: null });
            expect(
              (await client.rpc("pending_media_purge_paths", { p_limit: 100 }))
                .data,
            ).toEqual([]);
            expect(objectCount(path)).toBe("1");
          } else {
            await tx.run(call("delete_trash_item_forever"));
            const restore = Promise.resolve(
              client.rpc("restore_trash_item", params),
            );
            await expect.poll(() => blockedBy(label)).toBe("1");
            await tx.run("commit;");
            const result = await restore;
            expect(result.error).toBeNull();
            expect(result.data).toEqual([]);
            expect(
              (await client.from("entries").select("id").eq("id", entry)).data,
            ).toEqual([]);
            expect(await finishMediaPurges(client, owner)).toBe(true);
            expect(objectCount(path)).toBe("0");
          }
        } finally {
          await tx.close();
        }
      },
    );
  });
}
