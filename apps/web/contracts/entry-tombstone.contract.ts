import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { query, transaction } from "./helpers/local-sql";

type Account = {
  client: SupabaseClient;
  owner: string;
  /** Creates an Entry, moves it to Trash, and returns its Delete forever parameters. */
  trashedEntry: () => Promise<{
    id: string;
    revision: number;
    deletedAt: string;
  }>;
};

/** A disposable local account, removed with its rows afterwards. */
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
  const email = `entry-tombstone-${randomUUID()}@memotrail.local`;
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
    await run({
      client,
      owner,
      async trashedEntry() {
        const id = randomUUID();
        expect(
          (
            await client
              .from("entries")
              .insert({ id, owner_id: owner, body: "Queued capture" })
          ).error,
        ).toBeNull();
        const trashed = await client
          .from("entries")
          .update({ deleted_at: new Date().toISOString() })
          .eq("id", id)
          .select("revision,deleted_at")
          .single();
        expect(trashed.error).toBeNull();
        return {
          id,
          revision: trashed.data!.revision,
          deletedAt: trashed.data!.deleted_at,
        };
      },
    });
  } finally {
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
}

const blockedBy = (label: string) =>
  query(
    `select count(*) from pg_stat_activity a where (select pid from pg_stat_activity where application_name='${label}')=any(pg_blocking_pids(a.pid))`,
  );

function insertCapture(client: SupabaseClient, owner: string, id: string) {
  return Promise.resolve(
    client
      .from("entries")
      .insert({ id, owner_id: owner, body: "Queued capture" }),
  );
}

test("A capture sent again after Delete forever is refused with a final error", async () => {
  await withAccount(async ({ client, owner, trashedEntry }) => {
    const entry = await trashedEntry();
    const deleted = await client.rpc("delete_trash_item_forever", {
      p_item_kind: "entry",
      p_item_id: entry.id,
      p_expected_revision: entry.revision,
      p_expected_deleted_at: entry.deletedAt,
    });
    expect(deleted.error).toBeNull();
    expect(deleted.data).toHaveLength(1);

    // Deployed clients classify this SQLSTATE as a refusal, never as offline.
    const again = await insertCapture(client, owner, entry.id);
    expect(again.status).toBe(409);
    expect(again.error).toMatchObject({
      code: "23505",
      message: "entry_deleted_forever",
    });
    const photo = await client.rpc("register_entry_attachment", {
      p_entry_id: entry.id,
      p_attachment_id: randomUUID(),
      p_object_path: `${owner}/${entry.id}/${randomUUID()}.png`,
      p_original_filename: "trail.png",
      p_mime_type: "image/png",
      p_byte_size: 100,
      p_pixel_width: null,
      p_pixel_height: null,
    });
    expect(photo.error).toMatchObject({
      code: "23505",
      message: "entry_deleted_forever",
    });
    expect(
      (await client.from("entries").select("id").eq("id", entry.id)).data,
    ).toEqual([]);
    expect(
      query(
        `select count(*) from public.entry_tombstones where owner_id='${owner}' and entry_id='${entry.id}'`,
      ),
    ).toBe("1");
  });
});

test("A capture's photo cannot attach to its Entry in Trash, and says why", async () => {
  await withAccount(async ({ client, owner, trashedEntry }) => {
    const entry = await trashedEntry();
    const photo = await client.rpc("register_entry_attachment", {
      p_entry_id: entry.id,
      p_attachment_id: randomUUID(),
      p_object_path: `${owner}/${entry.id}/${randomUUID()}.png`,
      p_original_filename: "trail.png",
      p_mime_type: "image/png",
      p_byte_size: 100,
      p_pixel_width: null,
      p_pixel_height: null,
    });
    expect(photo.status).toBe(400);
    expect(photo.error).toMatchObject({
      code: "22023",
      message: "entry_in_trash",
    });
  });
});

test("A capture sent while Delete forever commits waits for it and is refused", async () => {
  await withAccount(async ({ client, owner, trashedEntry }) => {
    const entry = await trashedEntry();
    const label = `entry-tombstone-${owner}`;
    const tx = transaction();
    try {
      await tx.run(
        `set application_name='${label}'; begin; set local role authenticated; select set_config('request.jwt.claim.sub','${owner}',true);`,
      );
      await tx.run(
        `select count(*) from public.delete_trash_item_forever('entry','${entry.id}',${entry.revision},'${entry.deletedAt}');`,
      );
      // Without waiting for the deletion, this insert would replace the Entry
      // once the deletion commits.
      const insert = insertCapture(client, owner, entry.id);
      await expect.poll(() => blockedBy(label)).toBe("1");
      await tx.run("commit;");
      const result = await insert;
      expect(result.error).toMatchObject({
        code: "23505",
        message: "entry_deleted_forever",
      });
      expect(
        (await client.from("entries").select("id").eq("id", entry.id)).data,
      ).toEqual([]);
    } finally {
      await tx.close();
    }
  });
});
