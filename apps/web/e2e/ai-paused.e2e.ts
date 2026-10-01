import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("AI beta stays off, has no entry points, and blocks old clients without changing saved consent", async ({
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
    await page.getByRole("link", { name: /AI capabilities/ }).click();
    const toggle = page.getByRole("switch", { name: "AI capabilities" });
    await expect(toggle).not.toBeChecked();
    await expect(toggle).toBeDisabled();
    await expect(page.getByText("Beta", { exact: true })).toBeVisible();
    await expect(page.getByRole("switch")).toHaveCount(1);
    // Preserve SSR input styles while React finishes hydration.
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-ai-paused-desktop.png",
      fullPage: true,
    });
    await page.reload();
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await expect(toggle).toBeDisabled();
    await expect(toggle).not.toBeChecked();
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-ai-paused-mobile.png",
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
    await page.goto("/inbox");
    await page.getByRole("button", { name: "Organize", exact: true }).click();
    await expect(page.getByRole("dialog")).toBeVisible();
    await expect(
      page.getByRole("link", { name: "Explore with AI" }),
    ).toHaveCount(0);
    await expect(
      page.getByLabel("AI suggestions", { exact: true }),
    ).toHaveCount(0);
    expect(automaticRequests).toEqual([]);

    const requestHeaders: Record<string, string>[] = [
      { Origin: "http://127.0.0.1:3100" },
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
