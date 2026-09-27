import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("Unified AI search uses bilingual source evidence, explicit requests, and native bearer access", async ({
  page,
  context,
}) => {
  test.setTimeout(240_000);
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
  const email = `ai-search-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  if (!created.data.user) throw new Error("Local search fixture unavailable.");
  const ownerID = created.data.user.id,
    entryID = randomUUID(),
    afterID = randomUUID(),
    homeID = randomUUID();
  const live = process.env.MEMOTRAIL_E2E_LIVE_AI === "1";
  try {
    expect(
      (
        await page.request.post("/api/ai/search", {
          headers: { Origin: "http://127.0.0.1:3100" },
          data: {},
        })
      ).status(),
    ).toBe(401);
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
    if (!link.data.properties) throw new Error("Local sign-in unavailable.");
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
    const original =
      "2017年7月8日，我第一次滑雪。那时在想，学习新的技能让我更勇敢。";
    expect(
      (
        await client.from("entries").insert([
          {
            id: entryID,
            owner_id: ownerID,
            title: "雪山日记",
            body: original,
            item_kind: "entry",
            item_subtype: "first_time",
            date_precision: "day",
            occurred_start: "2017-07-08T12:00:00Z",
            occurred_timezone: "UTC",
          },
          {
            id: afterID,
            owner_id: ownerID,
            title: "电弧的原理",
            body: "今天学了电打火机使用电弧产生热量点燃蜡烛。",
            item_kind: "entry",
            item_subtype: "entry",
            date_precision: "day",
            occurred_start: "2026-01-07T12:00:00Z",
            occurred_timezone: "UTC",
          },
          {
            id: homeID,
            owner_id: ownerID,
            title: "New home",
            body: "Moved to California.",
            item_kind: "entity",
            item_subtype: "home",
            date_precision: "day",
            occurred_start: "2020-01-01T12:00:00Z",
            occurred_timezone: "UTC",
          },
        ])
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("homes").insert({
          entry_id: homeID,
          owner_id: ownerID,
          move_in_reason: "New job",
        })
      ).error,
    ).toBeNull();
    const headers = {
      Authorization: `Bearer ${signed.data.session!.access_token}`,
    };
    const request = {
      parameters: { q: "When did I first try skiing?" },
      timeZone: "UTC",
    };
    const invalid = await page.request.post("/api/ai/search", {
      headers,
      data: { ...request, parameters: { q: "skiing", sql: "select *" } },
    });
    expect(invalid.status()).toBe(400);
    expect(
      (
        await page.request.post("/api/ai/search", {
          headers: { Origin: "https://evil.test" },
          data: request,
        })
      ).status(),
    ).toBe(403);
    await page.goto("/search");
    await expect(
      page.getByRole("button", { name: "Ask AI", exact: true }),
    ).toHaveCount(0);
    await page
      .getByRole("searchbox", { name: "Search your Life Wiki" })
      .fill(request.parameters.q);
    await page.getByRole("button", { name: "Search", exact: true }).click();
    await expect(page).toHaveURL(/\/library\?q=/);
    const denied = await page.request.post("/api/ai/search", {
      headers,
      data: request,
    });
    expect(denied.ok()).toBe(false);
    expect(await denied.text()).toContain(
      live ? "Enable this AI feature" : "not configured",
    );
    expect((await client.rpc("ai_workspace")).data.recent_usage).toHaveLength(
      0,
    );
    if (live) {
      const workspace = (await client.rpc("ai_workspace")).data;
      expect(
        (
          await client.rpc("save_ai_preferences", {
            p_preferences: {
              ...workspace.preferences,
              enabled: true,
              search: true,
              monthly_budget_micros: 50000,
            },
            p_expected_revision: workspace.preferences.revision,
          })
        ).error,
      ).toBeNull();
      const completedSearch = await page.request.post("/api/ai/search", {
        headers,
        data: request,
        timeout: 65000,
      });
      const searchData = await completedSearch.json();
      expect(completedSearch.status(), JSON.stringify(searchData)).toBe(200);
      expect(
        searchData.sources?.length,
        JSON.stringify(searchData),
      ).toBeGreaterThan(0);
      expect(JSON.stringify(searchData)).toContain("2017");
    }
    if (live) {
      const learning = await page.request.post("/api/ai/search", {
        headers,
        data: {
          parameters: {
            q: "Show me things I learned about electricity.",
            type: "standard",
            from: "2026-01-01",
            to: "2026-12-31",
          },
          timeZone: "UTC",
        },
        timeout: 65000,
      });
      expect(learning.status(), await learning.text()).toBe(200);
      const result = await learning.json();
      expect(result.findings.length, JSON.stringify(result)).toBeGreaterThan(0);
      expect(
        result.sources.map((s: { recordID: string }) => s.recordID),
      ).toEqual([afterID]);
      const before = await page.request.post("/api/ai/search", {
        headers,
        data: {
          parameters: { q: "What was I thinking about before my last move?" },
          timeZone: "UTC",
        },
        timeout: 65000,
      });
      expect(before.status(), await before.text()).toBe(200);
      const prior = await before.json();
      expect(prior.findings.length, JSON.stringify(prior)).toBeGreaterThan(0);
      expect(
        prior.sources.some((s: { recordID: string }) => s.recordID === afterID),
      ).toBe(false);
      const missing = await page.request.post("/api/ai/search", {
        headers,
        data: {
          parameters: { q: "What is my passport number?" },
          timeZone: "UTC",
        },
        timeout: 65000,
      });
      expect(missing.status(), await missing.text()).toBe(200);
      expect((await missing.json()).insufficientEvidence).toBe(true);
      const usage = (await client.rpc("ai_workspace")).data;
      expect(
        usage.recent_usage.every(
          (u: { status: string }) => u.status === "completed",
        ),
      ).toBe(true);
      expect(usage.month_charged_micros).toBeLessThan(50000);
      console.log(
        `Synthetic AI search charged USD ${(usage.month_charged_micros / 1_000_000).toFixed(6)}.`,
      );
    }
    expect(
      (
        await client
          .from("entries")
          .select("body,revision,inbox_status")
          .eq("id", entryID)
          .single()
      ).data,
    ).toEqual({ body: original, revision: 1, inbox_status: "unreviewed" });
  } finally {
    expect((await admin.auth.admin.deleteUser(ownerID)).error).toBeNull();
  }
});
