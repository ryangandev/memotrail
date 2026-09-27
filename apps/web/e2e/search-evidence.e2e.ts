import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("Shared search evidence preserves keyword search and opens its actual source record", async ({
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
  const email = `search-evidence-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  if (!created.data.user) throw new Error("Local search fixture unavailable.");
  const ownerID = created.data.user.id,
    entryID = randomUUID();
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
    expect(
      (
        await client.from("entries").insert({
          id: entryID,
          owner_id: ownerID,
          title: "How an electric lighter works",
          body: "今天学了电打火机使用电弧点燃蜡烛。Electric arcs produce heat.",
          inbox_status: "organized",
          item_kind: "entry",
          item_subtype: "entry",
          date_precision: "day",
          occurred_start: "2026-01-05T12:00:00Z",
          occurred_timezone: "UTC",
        })
      ).error,
    ).toBeNull();
    const bearer = createClient(env.API_URL, env.ANON_KEY, {
      auth: { persistSession: false },
      global: {
        headers: {
          Authorization: `Bearer ${signed.data.session!.access_token}`,
        },
      },
    });
    const evidence = await bearer.rpc("archive_wiki_search_evidence", {
      p_queries: ["电弧", "electric arc"],
      p_order: "oldest",
    });
    expect(evidence.error).toBeNull();
    expect(evidence.data.entries).toHaveLength(1);
    expect(evidence.data.entries[0]).toMatchObject({
      id: entryID,
      date_precision: "day",
      title: "How an electric lighter works",
    });
    expect(evidence.data.entries[0]).not.toHaveProperty("attachments");
    expect(evidence.data.entries[0]).not.toHaveProperty("owner_id");
    let quickSearchRequests = 0;
    page.on("request", (request) => {
      if (new URL(request.url()).pathname === "/api/search/quick") {
        quickSearchRequests += 1;
      }
    });
    await page.goto("/");
    await page
      .getByRole("button", { name: "Search your trail", exact: true })
      .click();
    const commandPalette = page.getByRole("dialog", {
      name: "Search MemoTrail",
    });
    const quickSearch = commandPalette.getByRole("searchbox");
    await quickSearch.pressSequentially("electric", { delay: 15 });
    await expect(
      commandPalette.getByRole("button", {
        name: /How an electric lighter works/,
      }),
    ).toBeVisible();
    await expect(page).toHaveURL(/\/$/);
    expect(quickSearchRequests).toBe(1);
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-quick-search.png",
    });
    await commandPalette
      .getByRole("button", { name: /Search all for “electric”/ })
      .click();
    await expect(page).toHaveURL(/\/library\?q=electric$/);
    const searchSurface = page.getByRole("region", { name: "Entry search" });
    await searchSurface.getByText("Filters", { exact: true }).click();
    await expect(searchSurface).not.toContainText("Date filters include");
    await expect(searchSurface).toHaveCSS(
      "background-color",
      "rgba(0, 0, 0, 0)",
    );
    for (const width of [1500, 1050, 700, 390]) {
      await page.setViewportSize({ width, height: 900 });
      const dates = searchSurface.locator("[data-date-picker-field]");
      const from = await dates.nth(0).boundingBox();
      const to = await dates.nth(1).boundingBox();
      expect(from).not.toBeNull();
      expect(to).not.toBeNull();
      expect(from!.x + from!.width).toBeLessThanOrEqual(width);
      expect(to!.x + to!.width).toBeLessThanOrEqual(width);
      await expect
        .poll(() => page.evaluate(() => document.documentElement.scrollWidth))
        .toBeLessThanOrEqual(width);
      if (width === 1500 || width === 390) {
        await searchSurface.screenshot({
          animations: "disabled",
          path: `/private/tmp/memotrail-search-filters-${width}.png`,
        });
      }
    }
    await expect(
      page.getByRole("heading", { name: "How an electric lighter works" }),
    ).toBeVisible();
    await expect(
      page.getByText(
        "今天学了电打火机使用电弧点燃蜡烛。Electric arcs produce heat.",
      ),
    ).toBeVisible();
    // An organized Entry opens its current durable detail.
    await page
      .getByRole("link", { name: "How an electric lighter works" })
      .click();
    await expect(page).toHaveURL(
      new RegExp(`/items/${evidence.data.entries[0].id}$`),
    );
    await expect(
      page.getByRole("article", { name: "Current item", exact: true }),
    ).toBeVisible();
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.screenshot({
      path: "/private/tmp/memotrail-evidence-source-mobile.png",
      fullPage: true,
      caret: "initial",
    });
    await page.goto("/search?q=" + encodeURIComponent("电弧"));
    await expect(page).toHaveURL(/\/library\?q=/);
    await expect(
      page.getByRole("heading", { name: "How an electric lighter works" }),
    ).toBeVisible();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    const unchanged = await client
      .from("entries")
      .select("revision,inbox_status")
      .eq("id", entryID)
      .single();
    expect(unchanged.data).toEqual({ revision: 1, inbox_status: "organized" });
  } finally {
    expect((await admin.auth.admin.deleteUser(ownerID)).error).toBeNull();
  }
});
