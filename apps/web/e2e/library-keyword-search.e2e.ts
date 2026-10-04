import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("Canonical keyword search finds Entities", async ({ page, context }) => {
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
  const email = `library-keyword-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  expect(created.error).toBeNull();
  const owner = created.data.user!.id;
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
      cookies.map((c) => ({
        ...c,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax" as const,
      })),
    );
    const home = randomUUID();
    expect(
      (
        await client.from("entries").insert({
          id: home,
          owner_id: owner,
          title: "Learning 学习 flat",
          body: "A standalone Home",
          item_kind: "entity",
          item_subtype: "home",
          date_precision: "unknown",
          inbox_status: "organized",
        })
      ).error,
    ).toBeNull();
    expect(
      (await client.from("homes").insert({ entry_id: home, owner_id: owner }))
        .error,
    ).toBeNull();
    await page.goto("/search?q=" + encodeURIComponent("学习"));
    await expect(
      page.getByRole("link", { name: "Learning 学习 flat", exact: true }),
    ).toBeVisible();
    await page.screenshot({
      path: "/private/tmp/memotrail-library-keyword-desktop.png",
      fullPage: true,
      caret: "initial",
    });
    expect(
      (
        await client.from("entries").insert(
          Array.from({ length: 105 }, (_, index) => ({
            owner_id: owner,
            title: `Paged Memory ${String(index).padStart(3, "0")}`,
            inbox_status: "organized",
          })),
        )
      ).error,
    ).toBeNull();
    await page
      .getByRole("link", { name: "Learning 学习 flat", exact: true })
      .click();
    await expect(page).toHaveURL(new RegExp(`/homes/${home}$`));
    await expect(page.getByRole("main")).toContainText("A standalone Home");
    await expect(page.getByRole("textbox", { name: /^Story/ })).toHaveCount(0);
    await page.goto("/search?q=" + encodeURIComponent("Paged Memory"));
    const results = page.getByRole("region", { name: "Results", exact: true });
    await expect(results).toContainText("105 items");
    await expect(results.locator("article")).toHaveCount(25);
    await results.getByRole("link", { name: "Next", exact: true }).click();
    await expect(page).toHaveURL(/page=2/);
    await expect(
      results.getByRole("link", { name: /Paged Memory/ }).first(),
    ).toBeVisible();
    await page.goto(
      "/search?q=" + encodeURIComponent("学习") + "&type=writing",
    );
    await expect(
      page.getByText("No matching items", { exact: true }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: "Learning 学习 flat", exact: true }),
    ).toHaveCount(0);
    await expect(
      page.getByRole("link", { name: "Learning 学习 library", exact: true }),
    ).toHaveCount(0);
    await page.goto("/search?q=" + encodeURIComponent("学习"));
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.screenshot({
      path: "/private/tmp/memotrail-library-keyword-mobile.png",
      fullPage: true,
      caret: "initial",
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    const native = createClient(env.API_URL, env.ANON_KEY, {
      auth: { persistSession: false },
      global: {
        headers: {
          Authorization: `Bearer ${signed.data.session!.access_token}`,
        },
      },
    });
    const response = await native.rpc("search_wiki_items", {
      p_date_from: null,
      p_date_to: null,
      p_item_classifications: [],
      p_query: "学习",
      p_tag_names: [],
      p_limit: 20,
      p_offset: 0,
    });
    expect(response.error).toBeNull();
    expect(response.data).toHaveLength(1);
    expect(response.data[0].total_count).toBe(1);
    expect(
      response.data
        .map((item: { record_source: string }) => item.record_source)
        .sort(),
    ).toEqual(["entry"]);
    expect(
      response.data.map((item: { item_kind: string }) => item.item_kind),
    ).toEqual(["entity"]);
    const homeScope = await native.rpc("search_wiki_items", {
      p_date_from: null,
      p_date_to: null,
      p_item_classifications: ["home"],
      p_query: "学习",
      p_tag_names: [],
      p_limit: 20,
      p_offset: 0,
    });
    expect(homeScope.error).toBeNull();
    expect(homeScope.data).toHaveLength(1);
    expect(homeScope.data[0]).toMatchObject({
      item_kind: "entity",
      item_subtype: "home",
      record_source: "entry",
    });
    expect(
      (
        await client
          .from("entries")
          .update({ deleted_at: new Date().toISOString() })
          .eq("id", home)
      ).error,
    ).toBeNull();
    await page.goto(`/homes/${home}`);
    await expect(
      page.getByRole("heading", { name: "Home unavailable" }),
    ).toBeVisible();
    await page.goto("/search?q=" + encodeURIComponent("学习"));
    await expect(
      page.getByRole("link", { name: "Learning 学习 flat", exact: true }),
    ).toHaveCount(0);
  } finally {
    await page.close();
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
