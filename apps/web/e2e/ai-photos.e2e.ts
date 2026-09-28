import { execFileSync } from "node:child_process";
import { AI_CAPABILITIES_AVAILABLE } from "../src/lib/ai/availability";

test.skip(
  !AI_CAPABILITIES_AVAILABLE,
  "AI product paused; coverage is in ai-paused.e2e.ts.",
);
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import sharp from "sharp";
import { cleanupMediaFixture } from "./helpers/media-fixture";

test("AI photo suggestions require opt-in and share only synthetic previews", async ({
  page,
  context,
}) => {
  test.setTimeout(120_000);
  const env = JSON.parse(
    execFileSync("supabase", ["status", "-o", "json"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }),
  );
  expect(env.API_URL).toBe("http://127.0.0.1:54321");
  const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY);
  const email = `media-ai-photo-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  expect(created.error).toBeNull();
  const owner = created.data.user!.id,
    entry = randomUUID(),
    photo = randomUUID();
  try {
    const cookies: { name: string; value: string }[] = [];
    const client = createServerClient(env.API_URL, env.ANON_KEY, {
      cookies: {
        getAll: () => cookies,
        setAll: (values) => {
          cookies.push(...values.map(({ name, value }) => ({ name, value })));
        },
      },
    });
    const link = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    const signed = await client.auth.verifyOtp({
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
    expect(
      (
        await client.from("entries").insert({
          id: entry,
          owner_id: owner,
          title: "A visual note",
          body: "",
          date_precision: "unknown",
        })
      ).error,
    ).toBeNull();
    const bytes = await sharp(
      Buffer.from(
        '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="250"><rect width="400" height="250" fill="white"/><text x="30" y="145" font-size="64" fill="black">ARCHERY</text></svg>',
      ),
    )
      .png()
      .toBuffer();
    const path = `${owner}/${entry}/${photo}.png`;
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
          p_original_filename: "Synthetic.png",
          p_mime_type: "image/png",
          p_byte_size: bytes.length,
          p_pixel_width: 400,
          p_pixel_height: 250,
        })
      ).error,
    ).toBeNull();
    const endpoint = "/api/ai/suggestions";
    const request = {
      headers: { Authorization: `Bearer ${signed.data.session!.access_token}` },
      data: { entryID: entry, revision: 1 },
    };
    expect(
      (await (await page.request.post(endpoint, request)).json()).disabled,
    ).toBe(true);
    const workspace = (await client.rpc("ai_workspace")).data;
    expect(
      (
        await client.rpc("save_ai_preferences", {
          p_expected_revision: workspace.preferences.revision,
          p_preferences: {
            ...workspace.preferences,
            enabled: true,
            photo_analysis: true,
            monthly_budget_micros: 100000,
          },
        })
      ).error,
    ).toBeNull();
    const response = await page.request.post(endpoint, request);
    expect(response.status()).toBe(200);
    const result = await response.json();
    if (process.env.MEMOTRAIL_E2E_LIVE_AI !== "1") {
      expect(result.disabled).toBe(true);
      return;
    }
    expect(result.photoCount).toBe(1);
    expect(result.suggestion.status).toBe("proposed");
    expect(result.suggestion.suggestions.dateText).toBeNull();
    expect(JSON.stringify(result.suggestion.suggestions)).toMatch(
      /archer|弓|箭/i,
    );
    const repeat = await (await page.request.post(endpoint, request)).json();
    expect(repeat.suggestion.id).toBe(result.suggestion.id);
    const usage = (await client.rpc("ai_workspace")).data.recent_usage;
    expect(usage).toHaveLength(1);
    expect(usage[0]).toMatchObject({
      status: "completed",
      feature: "photo_analysis",
    });
    await page.goto("/inbox");
    await page.getByRole("button", { name: "Organize", exact: true }).click();
    const dialog = page.getByRole("dialog", { name: "Organize Capture" });
    await expect(
      dialog.getByText("Photo previews included: 1. Originals are not sent."),
    ).toBeVisible();
    const titleInput = dialog.getByLabel("Title", { exact: true });
    if (result.suggestion.suggestions.title) {
      await dialog.getByRole("button", { name: /Use title:/ }).click();
      await expect(titleInput).toHaveValue(result.suggestion.suggestions.title);
    } else {
      // A conservative model may decline to infer a title; manual editing must still work.
      await titleInput.fill("Archery inspiration");
      await expect(titleInput).toHaveValue("Archery inspiration");
    }
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-ai-photos-desktop.png",
      fullPage: true,
    });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-ai-photos-mobile-dark.png",
      fullPage: true,
    });
    expect(
      (
        await client
          .from("entries")
          .select("title,body,inbox_status,revision")
          .eq("id", entry)
          .single()
      ).data,
    ).toEqual({
      title: "A visual note",
      body: "",
      inbox_status: "unreviewed",
      revision: 1,
    });
    const original = await client.storage.from("entry-media").download(path);
    expect(Buffer.from(await original.data!.arrayBuffer())).toEqual(bytes);
  } finally {
    await cleanupMediaFixture(admin, owner, env.API_URL);
  }
});
