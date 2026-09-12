import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("Exploration persists across devices, recovers an interrupted response, and saves edited linked conclusions", async ({
  page,
  context,
}) => {
  test.setTimeout(180_000);
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
  const email = `explore-ui-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  const owner = created.data.user?.id;
  if (!owner) throw new Error("Synthetic exploration user unavailable.");
  const live = process.env.MEMOTRAIL_E2E_LIVE_AI === "1";
  const original =
    "今天学了电打火机利用电弧的热量点燃蜡烛。为什么不断学习很重要？";
  const entryID = randomUUID();
  try {
    expect(
      (
        await page.request.post("/api/ai/explore", {
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
    if (!link.data.properties)
      throw new Error("Synthetic sign-in unavailable.");
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
      })),
    );
    const headers = {
      Authorization: `Bearer ${signed.data.session!.access_token}`,
    };
    expect(
      (
        await client.from("entries").insert({
          id: entryID,
          owner_id: owner,
          title: "Learning journal",
          body: original,
          date_precision: "unknown",
        })
      ).error,
    ).toBeNull();
    const read = { action: "workspace", entryID };
    expect(
      (
        await page.request.post("/api/ai/explore", {
          headers,
          data: { ...read, ownerID: owner },
        })
      ).status(),
    ).toBe(400);
    expect(
      (
        await page.request.post("/api/ai/explore", {
          headers: { Origin: "https://evil.test" },
          data: read,
        })
      ).status(),
    ).toBe(403);
    await page.goto(`/history?entry=${entryID}`);
    await page
      .getByRole("link", { name: "Explore with AI", exact: true })
      .click();
    await expect(
      page.getByRole("region", { name: "Original Entry", exact: true }),
    ).toContainText(original);
    await page
      .getByLabel("Your question", { exact: true })
      .fill("An explicit question before opt-in");
    await page
      .getByRole("button", { name: "Send question", exact: true })
      .click();
    await expect(
      page.getByRole("alert").filter({
        hasText: live ? "Enable Explore with AI" : "not configured",
      }),
    ).toBeVisible();
    await expect(
      page.getByLabel("Your question", { exact: true }),
    ).toBeEnabled();
    expect((await client.rpc("ai_workspace")).data.recent_usage).toHaveLength(
      0,
    );
    const workspace = (await client.rpc("ai_workspace")).data;
    expect(
      (
        await client.rpc("save_ai_preferences", {
          p_preferences: {
            ...workspace.preferences,
            enabled: true,
            explore: true,
            monthly_budget_micros: 50000,
          },
          p_expected_revision: workspace.preferences.revision,
        })
      ).error,
    ).toBeNull();
    let submitted:
      | { requestID: string; question: string; sourceRevision: number }
      | undefined;
    if (!live) {
      // Persist a deterministic server result, then lose only the browser response.
      // This exercises the real workspace/save API, not a mock conversation store.
      await page.route("**/api/ai/explore", async (route) => {
        const data = route.request().postDataJSON();
        if (data.action !== "send") return route.continue();
        submitted = data;
        expect(
          (
            await admin.rpc("claim_exploration_turn", {
              p_owner_id: owner,
              p_entry_id: entryID,
              p_request_id: data.requestID,
              p_question: data.question,
              p_source_revision: data.sourceRevision,
            })
          ).data.claimed,
        ).toBe(true);
        expect(
          (
            await admin.rpc("finish_exploration_turn", {
              p_owner_id: owner,
              p_request_id: data.requestID,
              p_answer:
                "学习让我们更好地理解世界。这是 AI 的一种解释，不是你的原始记录。",
              p_model: "claude-haiku-4-5-20251001",
              p_error_code: null,
            })
          ).data,
        ).toBe(true);
        await route.abort("failed");
      });
    }
    await page
      .getByLabel("Your question", { exact: true })
      .fill(
        "根据这段记录，用中文简短说明持续学习有什么意义。不要编造我的经历。",
      );
    if (live) {
      const responsePromise = page.waitForResponse(
        (r) =>
          r.url().endsWith("/api/ai/explore") &&
          r.request().postDataJSON()?.action === "send",
      );
      await page
        .getByRole("button", { name: "Send question", exact: true })
        .click();
      const response = await responsePromise;
      submitted = response.request().postDataJSON();
      expect(response.status(), await response.text()).toBe(200);
      await response.finished();
    } else {
      await page
        .getByRole("button", { name: "Send question", exact: true })
        .click();
      await expect(
        page.getByRole("button", {
          name: "Retry the same request",
          exact: true,
        }),
      ).toBeEnabled();
      await page.unroute("**/api/ai/explore");
      await page.getByRole("button", { name: "Refresh conversation" }).click();
    }
    await expect(
      page.getByRole("button", { name: "Save as Entry", exact: true }),
    ).toBeVisible({ timeout: 65000 });
    await expect(
      page.getByLabel("Your question", { exact: true }),
    ).toBeEnabled();
    const nativeRead = await page.request.post("/api/ai/explore", {
      headers,
      data: read,
    });
    expect(nativeRead.status()).toBe(200);
    const data = await nativeRead.json();
    expect(data.turns).toHaveLength(1);
    expect(data.turns[0].source_snapshot.body).toBe(original);
    expect(data.turns[0].answer.length).toBeGreaterThan(10);
    if (live) {
      const before = (await client.rpc("ai_workspace")).data
        .month_charged_micros;
      const retry = await page.request.post("/api/ai/explore", {
        headers,
        data: { action: "send", entryID, ...submitted },
      });
      expect(retry.status()).toBe(200);
      expect((await client.rpc("ai_workspace")).data.month_charged_micros).toBe(
        before,
      );
      const followup = await page.request.post("/api/ai/explore", {
        headers,
        data: {
          action: "send",
          entryID,
          requestID: randomUUID(),
          sourceRevision: 1,
          question:
            "把你的上一个回答简化成一个我今天就能尝试的小行动，用一句话回答。",
        },
        timeout: 65000,
      });
      expect(followup.status(), await followup.text()).toBe(200);
      expect((await followup.json()).turns).toHaveLength(2);
    }
    await page.reload();
    await page
      .getByRole("button", { name: "Save as Entry", exact: true })
      .first()
      .click();
    await page
      .getByLabel("Conclusion title", { exact: true })
      .fill("My learning habit");
    await page
      .getByLabel("Conclusion text", { exact: true })
      .fill("我决定每天记录一个新学到的知识。这是我编辑过的结论。");
    if (!live) {
      await page.route("**/api/ai/explore", async (route) => {
        if (route.request().postDataJSON().action !== "save")
          return route.continue();
        const response = await route.fetch();
        expect(response.status()).toBe(200);
        await route.abort("failed");
      });
    }
    await page
      .getByRole("button", { name: "Save conclusion", exact: true })
      .click();
    if (!live) {
      await expect(
        page.getByRole("button", { name: "Retry same save", exact: true }),
      ).toBeEnabled();
      await expect(
        page.getByLabel("Conclusion text", { exact: true }),
      ).toBeDisabled();
      await page.unroute("**/api/ai/explore");
      await page
        .getByRole("button", { name: "Retry same save", exact: true })
        .click();
    }
    await expect(
      page.getByRole("status").filter({ hasText: "Conclusion saved to Inbox" }),
    ).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Refresh conversation", exact: true }),
    ).toBeEnabled();
    const open = page.getByRole("link", {
      name: "Open saved Entry",
      exact: true,
    });
    const savedID = (await open.getAttribute("href"))!.split("=")[1];
    await page.evaluate(() => window.scrollTo({ top: 0, behavior: "instant" }));
    await page.screenshot({
      path: "/private/tmp/memotrail-explore-desktop.png",
      fullPage: true,
    });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.evaluate(() => window.scrollTo({ top: 0, behavior: "instant" }));
    await page.screenshot({
      path: "/private/tmp/memotrail-explore-mobile.png",
      fullPage: true,
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await open.click();
    await expect(
      page.getByRole("region", { name: "Current version" }),
    ).toContainText("我决定每天记录一个新学到的知识");
    await page
      .getByRole("link", { name: "Open source Entry", exact: true })
      .click();
    await expect(
      page.getByRole("link", { name: "Open saved conclusion", exact: true }),
    ).toHaveAttribute("href", `/history?entry=${savedID}`);
    expect(
      (
        await client
          .from("entries")
          .select("body,revision,inbox_status")
          .eq("id", entryID)
          .single()
      ).data,
    ).toEqual({ body: original, revision: 2, inbox_status: "unreviewed" });
    expect(
      (
        await client
          .from("entries")
          .select("title,body,inbox_status")
          .eq("id", savedID)
          .single()
      ).data,
    ).toEqual({
      title: "My learning habit",
      body: "我决定每天记录一个新学到的知识。这是我编辑过的结论。",
      inbox_status: "unreviewed",
    });
    const usage = (await client.rpc("ai_workspace")).data;
    expect(usage.month_charged_micros).toBeLessThan(50000);
    if (live)
      console.log(
        `Synthetic exploration charged USD ${(usage.month_charged_micros / 1_000_000).toFixed(6)}.`,
      );
    else expect(usage.recent_usage).toHaveLength(0);
  } finally {
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
