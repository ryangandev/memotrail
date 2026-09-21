import { execFileSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";

test("Complete export snapshot pages preserve original media and history across concurrent devices", async () => {
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
  const email = `export-snapshot-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  const owner = created.data.user?.id;
  if (!owner) throw new Error("Synthetic export fixture unavailable.");
  const entryID = randomUUID(),
    attachmentID = randomUUID(),
    snapshotID = randomUUID();
  const path = `${owner}/${entryID}/${attachmentID}.png`;
  const original = Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=",
    "base64",
  );
  try {
    const link = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    if (!link.data.properties)
      throw new Error("Synthetic sign-in unavailable.");
    const first = createClient(env.API_URL, env.ANON_KEY, {
      auth: { persistSession: false },
    });
    const signed = await first.auth.verifyOtp({
      type: "magiclink",
      token_hash: link.data.properties.hashed_token,
    });
    expect(signed.error).toBeNull();
    const second = createClient(env.API_URL, env.ANON_KEY, {
      auth: { persistSession: false },
      global: {
        headers: {
          Authorization: `Bearer ${signed.data.session!.access_token}`,
        },
      },
    });
    const entries = Array.from({ length: 1005 }, (_, i) => ({
      id: i === 0 ? entryID : randomUUID(),
      owner_id: owner,
      title: `Record ${i}`,
      body: i === 0 ? "原始的生活记录" : "Synthetic export pagination fixture",
      date_precision: "unknown",
    }));
    expect((await first.from("entries").insert(entries)).error).toBeNull();
    expect(
      (
        await first.storage
          .from("entry-media")
          .upload(path, original, { contentType: "image/png" })
      ).error,
    ).toBeNull();
    expect(
      (
        await first.rpc("register_entry_attachment", {
          p_entry_id: entryID,
          p_attachment_id: attachmentID,
          p_object_path: path,
          p_original_filename: "原图.png",
          p_mime_type: "image/png",
          p_byte_size: original.length,
          p_pixel_width: 1,
          p_pixel_height: 1,
        })
      ).error,
    ).toBeNull();
    const snapshots = await Promise.all(
      Array.from({ length: 6 }, (_, i) =>
        (i % 2 ? first : second).rpc("create_export_snapshot", {
          p_request_id: snapshotID,
        }),
      ),
    );
    expect(
      snapshots.every((result) => !result.error),
      JSON.stringify(snapshots.map((s) => s.error)),
    ).toBe(true);
    const snapshot = snapshots[0].data;
    expect(new Set(snapshots.map((s) => s.data.captured_at)).size).toBe(1);
    expect(snapshot.datasets.entries).toBe(1005);
    expect(Object.keys(snapshot.datasets)).toHaveLength(27);
    const current = (
      await first.from("entries").select("revision").eq("id", entryID).single()
    ).data!;
    expect(
      (
        await first
          .from("entries")
          .update({
            body: "Updated after snapshot",
            revision: current.revision + 1,
          })
          .eq("id", entryID)
      ).error,
    ).toBeNull();
    let cursor = 0;
    const rows: {
      position: number;
      dataset: string;
      value: Record<string, unknown>;
    }[] = [];
    const counts: Record<string, number> = {};
    for (let page = 0; page < 100; page++) {
      const result = await (page % 2 ? first : second).rpc(
        "read_export_snapshot",
        { p_snapshot_id: snapshotID, p_after: cursor, p_limit: 250 },
      );
      expect(result.error).toBeNull();
      expect(result.data.snapshot.captured_at).toBe(snapshot.captured_at);
      rows.push(...result.data.rows);
      if (!result.data.has_more) break;
      expect(result.data.next_cursor).toBeGreaterThan(cursor);
      cursor = result.data.next_cursor;
    }
    expect(rows).toHaveLength(snapshot.row_count);
    expect(new Set(rows.map((r) => r.position)).size).toBe(rows.length);
    for (const row of rows)
      counts[row.dataset] = (counts[row.dataset] ?? 0) + 1;
    for (const [dataset, count] of Object.entries(snapshot.datasets))
      expect(counts[dataset] ?? 0).toBe(count);
    expect(
      rows.find((r) => r.dataset === "entries" && r.value.id === entryID)?.value
        .body,
    ).toBe("原始的生活记录");
    expect(rows.filter((r) => r.dataset === "entry_versions")).toHaveLength(
      snapshot.datasets.entry_versions,
    );
    const media = rows.find((r) => r.dataset === "media_objects")!.value;
    expect(media.available).toBe(true);
    expect(media.storage_version).toEqual(expect.any(String));
    expect(media.byte_size).toBe(String(original.length));
    expect(media.etag).toEqual(expect.any(String));
    const downloaded = await second.storage
      .from(String(media.bucket_id))
      .download(String(media.object_path));
    expect(downloaded.error).toBeNull();
    const hash = (value: Uint8Array) =>
      createHash("sha256").update(value).digest("hex");
    expect(hash(new Uint8Array(await downloaded.data!.arrayBuffer()))).toBe(
      hash(original),
    );
    expect(
      (
        await second.rpc("discard_export_snapshot", {
          p_snapshot_id: snapshotID,
        })
      ).data,
    ).toBe(true);
    expect(
      (await first.rpc("create_export_snapshot", { p_request_id: snapshotID }))
        .error?.message,
    ).toBe("export_expired");
    expect(
      (await first.from("entries").select("body").eq("id", entryID).single())
        .data?.body,
    ).toBe("Updated after snapshot");
    expect(
      (await first.storage.from("entry-media").download(path)).error,
    ).toBeNull();
  } finally {
    expect(
      (await admin.storage.from("entry-media").remove([path])).error,
    ).toBeNull();
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
