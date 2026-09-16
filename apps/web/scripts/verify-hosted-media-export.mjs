// Explicit production acceptance, synthetic records only, no AI requests.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash, randomBytes, randomUUID } from "node:crypto";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadEnvFile } from "node:process";
import { fileURLToPath } from "node:url";
import { createClient } from "@supabase/supabase-js";
import sharp from "sharp";

if (process.env.MEMOTRAIL_VERIFY_HOSTED_MEDIA_EXPORT !== "1") {
  throw new Error(
    "Set MEMOTRAIL_VERIFY_HOSTED_MEDIA_EXPORT=1 for isolated hosted acceptance.",
  );
}
loadEnvFile(fileURLToPath(new URL("../.env.local", import.meta.url)));
const appURL = "https://memotrail.ryangan.me";
const projectURL = "https://kaivkozeyuwzqrckmyqu.supabase.co";
assert(
  process.env.NEXT_PUBLIC_SUPABASE_URL === projectURL &&
    process.env.SUPABASE_SECRET_KEY &&
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  "Expected MemoTrail project and local Supabase credentials are required.",
);
const boundedFetch = (input, init = {}) =>
  fetch(input, {
    ...init,
    signal: AbortSignal.timeout(70_000),
    redirect: "error",
  });
const options = {
  auth: { persistSession: false, autoRefreshToken: false },
  global: { fetch: boundedFetch },
};
const admin = createClient(
  projectURL,
  process.env.SUPABASE_SECRET_KEY,
  options,
);
const client = createClient(
  projectURL,
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  options,
);
const marker = randomUUID();
const email = `hosted-media-export-${marker}@memotrail.local`;
const entryID = randomUUID();
const report = {
  app: appURL,
  fixture: email,
  passed: false,
  checks: [],
  issues: [],
  cleanup: "not-created",
};
let ownerID, token;
let stage = "authentication-denial";
const sha = (bytes) => createHash("sha256").update(bytes).digest("hex");
const checked = (value) => {
  assert.equal(value.error, null);
  return value.data;
};
async function post(endpoint, body, accessToken = token) {
  const response = await boundedFetch(`${appURL}${endpoint}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify(body),
  });
  report.checks.push({
    stage,
    endpoint: endpoint.split("?")[0],
    status: response.status,
    contentType: response.headers.get("content-type"),
    cache: response.headers.get("x-vercel-cache"),
  });
  return response;
}
async function json(endpoint, body) {
  const response = await post(endpoint, body);
  assert.equal(response.status, 200);
  return response.json();
}
// Inventory only the marked fixture's one Entry folder, never other owners.
async function fixturePaths(prefix, depth = 0) {
  assert(prefix.startsWith(`${ownerID}/${entryID}`) && depth <= 5);
  const items = checked(
    await admin.storage
      .from("entry-media")
      .list(prefix, { limit: 100, sortBy: { column: "name", order: "asc" } }),
  );
  assert(items.length < 100, "Refuse truncated fixture inventory.");
  const paths = [];
  for (const item of items) {
    assert(
      item.name && !item.name.includes("/") && ![".", ".."].includes(item.name),
    );
    const path = `${prefix}/${item.name}`;
    if (item.id) paths.push(path);
    else paths.push(...(await fixturePaths(path, depth + 1)));
  }
  return paths;
}

try {
  assert.equal(
    (await post("/api/export", { action: "list" }, "invalid-token")).status,
    401,
  );
  assert.equal(
    (await post("/api/media/urls", { paths: [] }, "invalid-token")).status,
    401,
  );
  stage = "synthetic-account-creation";
  report.cleanup = "creation-unconfirmed-inspect-fixture-before-retry";
  const created = checked(
    await admin.auth.admin.createUser({
      email,
      email_confirm: true,
      app_metadata: { memotrail_acceptance_fixture: marker },
    }),
  );
  ownerID = created.user?.id;
  assert(ownerID);
  report.cleanup = "pending";
  stage = "synthetic-session";
  const link = checked(
    await admin.auth.admin.generateLink({ type: "magiclink", email }),
  );
  const signed = checked(
    await client.auth.verifyOtp({
      type: "magiclink",
      token_hash: link.properties.hashed_token,
    }),
  );
  token = signed.session.access_token;
  stage = "hosted-session-verification";
  assert.equal(checked(await client.auth.getUser(token)).user.id, ownerID);
  const exportAuth = await post("/api/export", { action: "list" });
  const mediaAuth = await post("/api/media/urls", { paths: [] });
  assert.equal(exportAuth.status, 200);
  if (mediaAuth.status !== 200) {
    report.issues.push("canonical-media-authentication");
    // Read-only comparison, not a retry of a mutation or a production workaround.
    const uncached = await post(`/api/media/urls?acceptance=${marker}`, {
      paths: [],
    });
    report.mediaNonceStatus = uncached.status;
    const payload = await mediaAuth.json().catch(() => ({}));
    report.mediaAuthErrorRecognized =
      payload.error === "Sign in again or retry loading photos.";
  }
  stage = "synthetic-records";
  const body = "Hosted synthetic export only.\n合成记录，不含个人内容。";
  checked(
    await client.from("entries").insert({
      id: entryID,
      owner_id: ownerID,
      title: "Hosted media acceptance",
      body,
      date_precision: "age",
      occurred_label: "17岁",
    }),
  );
  const jpeg = await sharp({
    create: { width: 2400, height: 1200, channels: 3, background: "#316652" },
  })
    .jpeg()
    .withMetadata({ orientation: 6 })
    .withExif({
      IFD2: {
        DateTimeOriginal: "2017:07:08 12:34:56",
        OffsetTimeOriginal: "-04:00",
      },
      IFD3: {
        GPSLatitudeRef: "N",
        GPSLatitude: "39/1 57/1 0/1",
        GPSLongitudeRef: "W",
        GPSLongitude: "75/1 10/1 0/1",
      },
    })
    .toBuffer();
  const heic = Buffer.from(
    (
      await readFile(
        new URL(
          "../src/lib/media/fixtures/synthetic.heic.base64",
          import.meta.url,
        ),
        "utf8",
      )
    ).trim(),
    "base64",
  );
  const png = Buffer.concat([
    await sharp({
      create: { width: 1, height: 1, channels: 3, background: "#316652" },
    })
      .png()
      .toBuffer(),
    randomBytes(5 * 1024 * 1024),
  ]);
  const photos = [];
  for (const [bytes, ext, mime, dimensions] of [
    [jpeg, "jpg", "image/jpeg", [800, 1600]],
    [heic, "heic", "image/heic", [120, 80]],
    [png, "png", "image/png", [1, 1]],
  ]) {
    const id = randomUUID();
    const path = `${ownerID}/${entryID}/${id}.${ext}`;
    checked(
      await client.storage
        .from("entry-media")
        .upload(path, bytes, { contentType: mime, upsert: false }),
    );
    checked(
      await client.rpc("register_entry_attachment", {
        p_entry_id: entryID,
        p_attachment_id: id,
        p_object_path: path,
        p_original_filename: `synthetic.${ext}`,
        p_mime_type: mime,
        p_byte_size: bytes.length,
        p_pixel_width: null,
        p_pixel_height: null,
      }),
    );
    photos.push({ id, path, bytes, dimensions, ext });
  }
  stage = "private-preview-generation";
  try {
    const { urls } = await json("/api/media/urls", {
      paths: photos.map((p) => p.path),
    });
    for (const photo of photos) {
      const url = new URL(urls[photo.path]);
      // Never forward signed grants to a misconfigured host or log them.
      assert.equal(url.origin, appURL);
      assert.equal(url.pathname, "/api/media/image");
      const response = await boundedFetch(url);
      report.checks.push({ stage, format: photo.ext, status: response.status });
      assert.equal(response.status, 200);
      assert.equal(response.headers.get("content-type"), "image/webp");
      assert.match(response.headers.get("cache-control"), /private/);
      const preview = Buffer.from(await response.arrayBuffer());
      const metadata = await sharp(preview).metadata();
      assert.deepEqual([metadata.width, metadata.height], photo.dimensions);
      assert.equal(metadata.exif, undefined);
      const repeated = await boundedFetch(url);
      assert.equal(repeated.status, 200);
      assert.equal(
        sha(Buffer.from(await repeated.arrayBuffer())),
        sha(preview),
      );
      url.searchParams.set("variant", "thumbnail");
      const thumbnail = await boundedFetch(url);
      assert.equal(thumbnail.status, 200);
      const small = await sharp(
        Buffer.from(await thumbnail.arrayBuffer()),
      ).metadata();
      assert(Math.max(small.width, small.height) <= 400);
      const original = checked(
        await client.storage.from("entry-media").download(photo.path),
      );
      assert.equal(
        sha(Buffer.from(await original.arrayBuffer())),
        sha(photo.bytes),
      );
      stage = "photo-metadata";
      const facts = await json(
        `/api/media/metadata?attachmentId=${photo.id}`,
        {},
      );
      assert.equal(facts.attachmentId, photo.id);
      assert(facts.sourceVersion);
      if (photo.ext === "jpg") {
        assert.equal(facts.calendarDate, "2017-07-08");
        assert.equal(facts.offset, "-04:00");
        assert(Math.abs(facts.latitude - 39.95) < 0.00001);
        assert(Math.abs(facts.longitude + 75 + 1 / 6) < 0.00001);
      }
      stage = "private-preview-generation";
    }
    report.mediaPassed = true;
  } catch {
    report.mediaPassed = false;
    report.issues.push(`media-failed-at-${stage}`);
  }
  stage = "export-snapshot";
  const snapshotID = randomUUID();
  const { snapshot } = await json("/api/export", {
    action: "create",
    id: snapshotID,
  });
  assert.equal(snapshot.id, snapshotID);
  assert.equal(snapshot.datasets.entries, 1);
  assert.equal(Object.keys(snapshot.datasets).length, 30);
  const reused = await json("/api/export", {
    action: "create",
    id: snapshotID,
  });
  assert.equal(reused.snapshot.captured_at, snapshot.captured_at);
  stage = "export-stream-and-integrity";
  const archive = await post("/api/export", {
    action: "download",
    id: snapshotID,
  });
  assert.equal(archive.status, 200);
  assert.equal(archive.headers.get("content-type"), "application/zip");
  const zip = Buffer.from(await archive.arrayBuffer());
  assert(zip.length > 4.5 * 1024 * 1024 && zip.length < 12 * 1024 * 1024);
  const markerBytes = Buffer.from("MEMOTRAIL_EXPORT_V1_COMPLETE");
  const tail = zip.subarray(-(22 + markerBytes.length));
  assert.equal(tail.readUInt32LE(0), 0x06054b50);
  assert.equal(tail.readUInt16LE(20), markerBytes.length);
  assert(tail.subarray(22).equals(markerBytes));
  const directory = await mkdtemp(join(tmpdir(), "memotrail-hosted-export-"));
  const zipPath = join(directory, "synthetic-export.zip");
  await writeFile(zipPath, zip, { flag: "wx", mode: 0o600 });
  report.artifact = zipPath;
  execFileSync("unzip", ["-tq", zipPath], { stdio: "pipe", timeout: 30_000 });
  const read = (name) =>
    execFileSync("unzip", ["-p", zipPath, name], {
      maxBuffer: 12 * 1024 * 1024,
      timeout: 30_000,
    });
  const manifest = JSON.parse(read("manifest.json"));
  assert.equal(manifest.snapshot.id, snapshotID);
  for (const [name, count] of Object.entries(snapshot.datasets)) {
    assert(/^[a-z_]+$/.test(name));
    assert.equal(JSON.parse(read(`data/${name}.json`)).length, count);
  }
  const entries = JSON.parse(read("data/entries.json"));
  assert.equal(entries[0].owner_id, ownerID);
  assert.equal(entries[0].body, body);
  assert(read(`entries/${entryID}.md`).toString().includes(body));
  assert(
    read(`entries/${entryID}.md`).toString().includes('occurred_label: "17岁"'),
  );
  for (const name of ["homes", "vehicles"])
    assert(read(`tables/${name}.csv`).toString().includes('"id"'));
  const checksums = JSON.parse(read("checksums.json"));
  assert.equal(checksums.complete, true);
  for (const photo of photos) {
    const checksum = checksums.media.find(
      (item) => item.attachment_id === photo.id,
    );
    assert.equal(checksum.sha256, sha(photo.bytes));
    assert(
      /^media\/[a-f0-9-]+-original\.(jpg|heic|png)$/.test(
        checksum.archive_path,
      ),
    );
    assert.equal(sha(read(checksum.archive_path)), sha(photo.bytes));
  }
  report.archiveBytes = zip.length;
  report.originalsVerified = photos.length;
  report.datasetCount = Object.keys(snapshot.datasets).length;
  stage = "snapshot-discard";
  assert.equal(
    (await json("/api/export", { action: "discard", id: snapshotID }))
      .discarded,
    true,
  );
  assert.equal(
    (await post("/api/export", { action: "download", id: snapshotID })).status,
    410,
  );
  report.exportPassed = true;
  report.passed = report.mediaPassed && report.issues.length === 0;
  if (!report.passed) process.exitCode = 1;
} catch {
  report.failure = `Failed at ${stage}; no raw SDK errors, tokens, signed URLs, or record contents are logged.`;
  process.exitCode = 1;
} finally {
  if (ownerID) {
    try {
      const found = checked(await admin.auth.admin.getUserById(ownerID));
      assert.equal(found.user.email, email);
      assert.equal(
        found.user.app_metadata.memotrail_acceptance_fixture,
        marker,
      );
      const paths = await fixturePaths(`${ownerID}/${entryID}`);
      if (paths.length)
        checked(await admin.storage.from("entry-media").remove(paths));
      assert.equal((await fixturePaths(`${ownerID}/${entryID}`)).length, 0);
      checked(await admin.auth.admin.deleteUser(ownerID));
      const absent = await admin.auth.admin.getUserById(ownerID);
      assert.equal(absent.error?.status, 404);
      report.cleanup = "removed-exact-synthetic-objects-and-account";
      report.removedObjects = paths.length;
    } catch {
      report.passed = false;
      report.cleanup = "unconfirmed-inspect-exact-fixture-before-retry";
      process.exitCode = 1;
    }
  }
  console.log(JSON.stringify(report, null, 2));
}
