import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect, type Request } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import sharp from "sharp";
import { cleanupMediaFixture } from "./helpers/media-fixture";

test("Paused AI has no setting or entry point and blocks old clients without changing saved consent", async ({
  baseURL,
  page,
  context,
}) => {
  const env = JSON.parse(
    execFileSync("supabase", ["status", "-o", "json"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }),
  );
  expect(env.API_URL).toMatch(/^http:\/\/127\.0\.0\.1:\d+$/);
  const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
  const email = `ai-paused-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  expect(created.error).toBeNull();
  const owner = created.data.user!.id;
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  const automaticRequests: string[] = [];
  page.on("request", (request) => {
    if (request.url().includes("/api/ai/"))
      automaticRequests.push(request.url());
  });
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
    expect(signed.error).toBeNull();
    await context.addCookies(
      cookies.map((cookie) => ({
        ...cookie,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax" as const,
      })),
    );
    const workspace = await client.rpc("ai_workspace");
    expect(workspace.error).toBeNull();
    const enabled = await client.rpc("save_ai_preferences", {
      p_preferences: {
        ...workspace.data.preferences,
        enabled: true,
        classification: true,
        tagging: true,
        search: true,
        explore: true,
        photo_analysis: true,
      },
      p_expected_revision: workspace.data.preferences.revision,
    });
    expect(enabled.error).toBeNull();
    const entry = randomUUID();
    expect(
      (
        await client.from("entries").insert({
          id: entry,
          owner_id: owner,
          body: "A quiet afternoon. 一个安静的下午。",
        })
      ).error,
    ).toBeNull();

    await page.goto("/settings");
    // The paused AI capabilities setting is gone; Settings offers only the review switches,
    // and an old bookmark lands on them.
    await expect(
      page.getByRole("link", { name: /AI capabilities/ }),
    ).toHaveCount(0);
    await expect(page.getByText("Beta", { exact: true })).toHaveCount(0);
    const reviews = page.getByRole("checkbox", {
      name: "Chapter and year reviews",
    });
    await expect(reviews).not.toBeChecked();
    await expect(
      page.getByRole("checkbox", { name: "Suggest Chapters" }),
    ).not.toBeChecked();
    await page.goto("/settings/ai");
    await expect(page).toHaveURL(/\/settings#reviews$/);
    // Preserve SSR input styles while React finishes hydration.
    await page.screenshot({
      caret: "initial",
      path: test.info().outputPath("memotrail-ai-paused-desktop.png"),
      fullPage: true,
    });
    await page.reload();
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await expect(reviews).not.toBeChecked();
    await page.screenshot({
      caret: "initial",
      path: test.info().outputPath("memotrail-ai-paused-mobile.png"),
      fullPage: true,
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await page
      .getByRole("button", { name: "More destinations", exact: true })
      .click();
    await expect(
      page.getByRole("link", { name: "Explore with AI" }),
    ).toHaveCount(0);
    await page.goto(`/explore?entry=${entry}`);
    await expect(page).toHaveURL(/\/library$/);
    await expect(page.getByRole("button", { name: "Ask AI" })).toHaveCount(0);
    await page.goto(`/items/${entry}`);
    await expect(page.getByRole("main")).toContainText("A quiet afternoon.");
    await expect(
      page.getByRole("link", { name: "Explore with AI" }),
    ).toHaveCount(0);
    await page.getByRole("button", { name: "Edit Entry", exact: true }).click();
    await expect(page.getByRole("dialog")).toBeVisible();
    await expect(
      page.getByRole("link", { name: "Explore with AI" }),
    ).toHaveCount(0);
    await expect(
      page.getByLabel("AI suggestions", { exact: true }),
    ).toHaveCount(0);
    expect(automaticRequests).toEqual([]);

    const requestHeaders: Record<string, string>[] = [
      { Origin: baseURL! },
      { Authorization: `Bearer ${signed.data.session!.access_token}` },
    ];
    for (const endpoint of ["connection", "suggestions", "search", "explore"]) {
      for (const headers of requestHeaders) {
        const result = await page.request.post(`/api/ai/${endpoint}`, {
          headers,
          data: { entryID: entry, revision: 1 },
        });
        expect(result.status()).toBe(503);
        expect((await result.json()).code).toBe("ai_paused");
      }
    }
    const after = await client.rpc("ai_workspace");
    expect(after.data.preferences.enabled).toBe(true);
    expect(after.data.recent_usage).toHaveLength(0);
    expect(
      (await client.from("entries").select("body").eq("id", entry).single())
        .data?.body,
    ).toBe("A quiet afternoon. 一个安静的下午。");
    expect(errors).toEqual([]);
  } finally {
    await page.close();
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});

// The e2e server is configured like Production, with a scripted provider behind it; the pause
// must still stop capture follow-up work before any provider call.
test("Captures with saved AI consent start no paused suggestion work", async ({
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
  expect(env.API_URL).toMatch(/^http:\/\/127\.0\.0\.1:\d+$/);
  const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
  const email = `media-ai-paused-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  expect(created.error).toBeNull();
  const owner = created.data.user!.id;
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  const aiRequests: string[] = [];
  const pendingActions = new Set<Request>();
  page.on("request", (request) => {
    if (request.url().includes("/api/ai/")) aiRequests.push(request.url());
    if (request.headers()["next-action"]) pendingActions.add(request);
  });
  page.on("requestfinished", (request) => pendingActions.delete(request));
  page.on("requestfailed", (request) => pendingActions.delete(request));
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
    expect(
      (
        await client.auth.verifyOtp({
          type: "magiclink",
          token_hash: link.data.properties!.hashed_token,
        })
      ).error,
    ).toBeNull();
    await context.addCookies(
      cookies.map((cookie) => ({
        ...cookie,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax" as const,
      })),
    );
    const workspace = await client.rpc("ai_workspace");
    expect(workspace.error).toBeNull();
    expect(
      (
        await client.rpc("save_ai_preferences", {
          p_preferences: {
            ...workspace.data.preferences,
            enabled: true,
            classification: true,
            tagging: true,
            photo_analysis: true,
          },
          p_expected_revision: workspace.data.preferences.revision,
        })
      ).error,
    ).toBeNull();

    await page.goto("/");
    const capture = page.getByRole("form", {
      name: "Quick capture",
      exact: true,
    });
    const text = capture.getByRole("textbox", {
      name: "Entry text",
      exact: true,
    });
    const save = capture.getByRole("button", {
      name: "Save",
      exact: true,
    });
    const toast = page.locator("[data-sonner-toast]");
    await text.fill("A quiet afternoon by the lake.");
    await save.click();
    await expect(toast.filter({ hasText: "Saved to Library." })).toBeVisible();

    await capture.locator('input[type="file"]').setInputFiles({
      name: "lake.png",
      mimeType: "image/png",
      buffer: await sharp({
        create: { width: 320, height: 240, channels: 3, background: "#426e83" },
      })
        .png()
        .toBuffer(),
    });
    await text.fill("The lake at dusk.");
    await save.click();
    await expect(
      toast.filter({ hasText: "Saved to Library with 1 photo." }),
    ).toBeVisible();

    const entries = await client
      .from("entries")
      .select("body")
      .order("created_at");
    expect(entries.error).toBeNull();
    expect(entries.data).toEqual([
      { body: "A quiet afternoon by the lake." },
      { body: "The lake at dusk." },
    ]);
    // Suggestion work used to start after each action responded, so watch a short window.
    await expect.poll(() => pendingActions.size).toBe(0);
    for (let check = 0; check < 6; check += 1) {
      const suggestions = await admin
        .from("ai_suggestions")
        .select("status,request_scope")
        .eq("owner_id", owner);
      expect(suggestions.error).toBeNull();
      expect(suggestions.data).toEqual([]);
      await page.waitForTimeout(500);
    }
    const after = await client.rpc("ai_workspace");
    expect(after.data.preferences.enabled).toBe(true);
    expect(after.data.recent_usage).toHaveLength(0);
    expect(aiRequests).toEqual([]);
    expect(errors).toEqual([]);
  } finally {
    await page.close();
    await cleanupMediaFixture(admin, owner, env.API_URL);
  }
});
