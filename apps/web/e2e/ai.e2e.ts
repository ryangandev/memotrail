import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("AI consent, settings persistence, API authentication, and bounded connection test", async ({
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
  const email = `ai-${randomUUID()}@memotrail.local`;
  const { data: created, error } = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  if (error || !created.user)
    throw new Error("Could not create local AI fixture.");
  const ownerID = created.user.id;
  const live = process.env.MEMOTRAIL_E2E_LIVE_AI === "1";
  try {
    const denied = await page.request.post("/api/ai/connection", {
      headers: { Origin: "http://127.0.0.1:3100" },
    });
    expect(denied.status()).toBe(401);
    const invalid = await page.request.post("/api/ai/connection", {
      headers: { Authorization: "Bearer invalid-token" },
    });
    expect(invalid.status()).toBe(401);
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
      type: "magiclink",
      email,
    });
    if (!link.data.properties)
      throw new Error("Local fixture sign-in unavailable.");
    const signed = await client.auth.verifyOtp({
      type: "magiclink",
      token_hash: link.data.properties.hashed_token,
    });
    expect(signed.error).toBeNull();
    await context.addCookies(
      cookies.map((c) => ({
        ...c,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax" as const,
        httpOnly: false,
      })),
    );
    await page.goto("/settings/ai");
    const errors: string[] = [];
    page.on("pageerror", (e) => errors.push(e.message));
    const enable = page.getByRole("checkbox", { name: /Enable AI assistance/ });
    await expect(enable).not.toBeChecked();
    await expect(
      page.getByRole("checkbox", { name: /Photo analysis/ }),
    ).not.toBeChecked();
    await enable.check();
    await page.getByLabel("Monthly budget (USD)").fill("0.03");
    await page.getByRole("button", { name: "Save AI settings" }).click();
    await expect(page.getByRole("status")).toContainText(
      "saved across your devices",
    );
    const { data: workspace } = await client.rpc("ai_workspace");
    expect(workspace.preferences.enabled).toBe(true);
    expect(workspace.preferences.monthly_budget_micros).toBe(30000);
    expect(workspace.preferences.photo_analysis).toBe(false);
    const crossOrigin = await page.request.post("/api/ai/connection", {
      headers: { Origin: "https://evil.test" },
    });
    expect(crossOrigin.status()).toBe(403);
    if (live) {
      await page.getByRole("button", { name: "Test connection" }).click();
      await expect(page.getByRole("status")).toContainText(
        "Anthropic connection verified",
        { timeout: 35000 },
      );
      const { data: usage } = await client.rpc("ai_workspace");
      expect(usage.recent_usage).toHaveLength(1);
      expect(usage.recent_usage[0].status).toBe("completed");
      expect(usage.month_charged_micros).toBeGreaterThan(0);
      expect(usage.month_charged_micros).toBeLessThan(1000);
      // Verify the iOS bearer path without cookies, after lowering the budget to zero.
      const noBudget = await client.rpc("save_ai_preferences", {
        p_preferences: { ...usage.preferences, monthly_budget_micros: 0 },
        p_expected_revision: usage.preferences.revision,
      });
      expect(noBudget.error).toBeNull();
      const bearer = await page.request.post("/api/ai/connection", {
        headers: {
          Authorization: `Bearer ${signed.data.session!.access_token}`,
        },
      });
      expect(bearer.status()).toBe(429);
    } else {
      await expect(
        page.getByRole("button", { name: "Test connection" }),
      ).toBeDisabled();
      const response = await page.request.post("/api/ai/connection", {
        headers: { Origin: "http://127.0.0.1:3100" },
      });
      expect(response.status()).toBe(503);
    }
    await page.reload();
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await expect(enable).toBeChecked();
    await page.screenshot({
      path: "/private/tmp/memotrail-ai-settings-mobile.png",
      fullPage: true,
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);
    await enable.uncheck();
    await page.getByRole("button", { name: "Save AI settings" }).click();
    await expect(page.getByRole("status")).toContainText(
      "saved across your devices",
    );
    await expect(
      page.getByRole("button", { name: "Test connection" }),
    ).toBeDisabled();
    expect(errors).toEqual([]);
  } finally {
    const result = await admin.auth.admin.deleteUser(ownerID);
    if (result.error)
      throw new Error("Could not clean up the local AI fixture.");
  }
});
