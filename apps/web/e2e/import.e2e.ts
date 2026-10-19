import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { writeFile } from "node:fs/promises";
import { test, expect, type BrowserContext } from "@playwright/test";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import { buildZip, tinyPng } from "../src/lib/import/test-zip";

/** Runs a scenario as its own disposable, signed-in account and cleans up what it made. */
async function asNewUser(
  context: BrowserContext,
  scenario: (admin: SupabaseClient, owner: string) => Promise<void>,
) {
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
  const email = `import-flow-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  const owner = created.data.user?.id;
  if (!owner) throw new Error("Synthetic import fixture unavailable.");
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
      email,
      type: "magiclink",
    });
    const signed = await client.auth.verifyOtp({
      token_hash: link.data.properties!.hashed_token,
      type: "magiclink",
    });
    expect(signed.error).toBeNull();
    await context.addCookies(
      cookies.map((c) => ({
        ...c,
        domain: "127.0.0.1",
        httpOnly: false,
        path: "/",
        sameSite: "Lax",
      })),
    );
    await scenario(admin, owner);
  } finally {
    const files = await admin
      .from("attachments")
      .select("object_path")
      .eq("owner_id", owner);
    if (files.data?.length)
      await admin.storage
        .from("entry-media")
        .remove(files.data.map((file) => file.object_path));
    const staged = await admin.storage.from("import-staging").list(owner);
    if (staged.data?.length)
      await admin.storage
        .from("import-staging")
        .remove(staged.data.map((file) => `${owner}/${file.name}`));
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
}

test("A Markdown ZIP previews, imports with its photo and dates, and a second import adds nothing", async ({
  context,
  page,
}, testInfo) => {
  test.setTimeout(180_000);
  await asNewUser(context, async (admin, owner) => {
    const zipPath = testInfo.outputPath("notes.zip");
    await writeFile(
      zipPath,
      await buildZip({
        "Notes/Trips/Lisbon.md": [
          "---",
          "date: 2024-05-12",
          "tags: [travel]",
          "---",
          "Custard tarts by the river.",
          "",
          "![](lisbon.png)",
        ].join("\n"),
        "Notes/Trips/lisbon.png": tinyPng,
        "Notes/Undated.md": "A thought with no date.",
        "Notes/Winter.md": "# Winter walk\n\nSnow on the path.",
      }),
    );

    await page.goto("/settings");
    await page
      .getByRole("main")
      .getByRole("link", { name: "Import", exact: true })
      .click();
    await expect(page.getByRole("heading", { name: "Import" })).toBeVisible();

    const choose = async () => {
      await page.getByRole("button", { name: "Markdown folder" }).click();
      await page.setInputFiles('input[type="file"]', zipPath);
    };

    // First import: preview, then run.
    await choose();
    await expect(
      page.getByRole("heading", { name: /Found 3 Entries in notes\.zip/ }),
    ).toBeVisible({ timeout: 60_000 });
    await expect(page.getByText("Trips", { exact: true })).toBeVisible();
    await expect(page.getByText("Custard tarts by the river.")).toBeVisible();
    await page.getByRole("button", { name: "Import 3 Entries" }).click();
    await expect(
      page.getByRole("heading", { name: "Import finished" }),
    ).toBeVisible({ timeout: 120_000 });
    await expect(page.getByText("New Entries").locator("..")).toContainText(
      "3",
    );

    const entries = await admin
      .from("entries")
      .select("id,title,date_precision,occurred_start,occurred_timezone")
      .eq("owner_id", owner)
      .order("title");
    expect(entries.error).toBeNull();
    expect(entries.data).toHaveLength(3);
    // The note with a date is kept at day precision; the others are honestly undated.
    const precisions = entries
      .data!.map((entry) => entry.date_precision)
      .sort();
    expect(precisions).toEqual(["day", "unknown", "unknown"]);
    const lisbon = entries.data!.find(
      (entry) => entry.date_precision === "day",
    );
    expect(lisbon?.occurred_start).toMatch(/^2024-05-12T/);
    const attachments = await admin
      .from("attachments")
      .select("id")
      .eq("owner_id", owner);
    expect(attachments.data).toHaveLength(1);

    // The Entries are ordinary Entries in the Library.
    await page.getByRole("link", { name: "See them in Library" }).click();
    await expect(page).toHaveURL(/\/library\?tag=Imported/, {
      timeout: 30_000,
    });
    await expect(page.getByText("Winter walk")).toBeVisible();

    // Importing the same file again adds nothing.
    await page.goto("/settings/import");
    await page.getByRole("button", { name: "Import another file" }).click();
    await choose();
    await expect(
      page.getByRole("heading", { name: /Found 3 Entries/ }),
    ).toBeVisible({ timeout: 60_000 });
    await expect(page.getByText(/already in MemoTrail/)).toBeVisible();
    await page.getByRole("button", { name: "Import 3 Entries" }).click();
    await expect(
      page.getByRole("heading", { name: "Import finished" }),
    ).toBeVisible({ timeout: 120_000 });
    await expect(page.getByText("Already there").locator("..")).toContainText(
      "3",
    );
    const again = await admin
      .from("entries")
      .select("id", { count: "exact", head: true })
      .eq("owner_id", owner);
    expect(again.count).toBe(3);
  });
});

test("A Day One export keeps exact times, zones, tags, and places, and can be undone", async ({
  context,
  page,
}, testInfo) => {
  test.setTimeout(180_000);
  await asNewUser(context, async (admin, owner) => {
    const zipPath = testInfo.outputPath("dayone.zip");
    await writeFile(
      zipPath,
      await buildZip({
        "Journal.json": JSON.stringify({
          entries: [
            {
              creationDate: "2024-05-12T14:03:00Z",
              location: { localityName: "Lisbon", country: "Portugal" },
              photos: [{ identifier: "P1", md5: "abc123", type: "png" }],
              tags: ["travel"],
              text: "# Lisbon day\n\nCustard tarts\\.\n\n![](dayone-moment://P1)",
              timeZone: "Europe/Lisbon",
              uuid: "DAYONE-1",
            },
            {
              creationDate: "2024-05-13T09:00:00Z",
              text: "Rain all day.",
              timeZone: "Europe/Lisbon",
              uuid: "DAYONE-2",
            },
          ],
          metadata: { version: "1.0" },
        }),
        "photos/abc123.png": tinyPng,
      }),
    );

    await page.goto("/settings/import");
    await page.getByRole("button", { name: "Day One" }).click();
    await page.setInputFiles('input[type="file"]', zipPath);
    await expect(
      page.getByRole("heading", { name: /Found 2 Entries in dayone\.zip/ }),
    ).toBeVisible({ timeout: 60_000 });
    await page.getByRole("button", { name: "Import 2 Entries" }).click();
    await expect(
      page.getByRole("heading", { name: "Import finished" }),
    ).toBeVisible({ timeout: 120_000 });

    const entries = await admin
      .from("entries")
      .select(
        "id,title,date_precision,occurred_start,occurred_timezone,deleted_at",
      )
      .eq("owner_id", owner)
      .order("occurred_start");
    expect(entries.data).toHaveLength(2);
    expect(entries.data![0]).toMatchObject({
      date_precision: "exact",
      occurred_timezone: "Europe/Lisbon",
      title: "Lisbon day",
    });
    expect(new Date(entries.data![0].occurred_start).toISOString()).toBe(
      "2024-05-12T14:03:00.000Z",
    );
    const tags = await admin
      .from("entry_tags")
      .select("tag_id, tags(name)")
      .eq("entry_id", entries.data![0].id);
    expect(JSON.stringify(tags.data)).toContain("travel");
    const attachments = await admin
      .from("attachments")
      .select("id")
      .eq("owner_id", owner);
    expect(attachments.data).toHaveLength(1);

    // Undo moves the Entries to Trash.
    await page.getByRole("button", { name: "Undo this import" }).click();
    await page.getByRole("button", { name: "Move to Trash" }).click();
    await expect(async () => {
      const trashed = await admin
        .from("entries")
        .select("id")
        .eq("owner_id", owner)
        .not("deleted_at", "is", null);
      expect(trashed.data).toHaveLength(2);
    }).toPass({ timeout: 30_000 });
  });
});
