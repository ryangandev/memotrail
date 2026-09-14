import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("Global keyword search finds standalone People and Places without deferred Habits", async ({
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
    const person = randomUUID(),
      place = randomUUID(),
      habit = randomUUID();
    expect(
      (
        await client.from("people").insert({
          id: person,
          owner_id: owner,
          name: "Learning 学习 partner",
          notes: "A standalone Person",
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("places").insert({
          id: place,
          owner_id: owner,
          name: "Learning 学习 library",
          notes: "A standalone Place",
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client
          .from("habits")
          .insert({ id: habit, owner_id: owner, name: "Learning 学习 daily" })
      ).error,
    ).toBeNull();
    await page.goto("/search?q=" + encodeURIComponent("学习"));
    await expect(
      page.getByRole("link", { name: "Learning 学习 partner", exact: true }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: "Learning 学习 library", exact: true }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: "Learning 学习 daily", exact: true }),
    ).toHaveCount(0);
    await page.screenshot({
      path: "/private/tmp/memotrail-library-keyword-desktop.png",
      fullPage: true,
    });
    expect(
      (
        await client.from("people").insert(
          Array.from({ length: 105 }, (_, index) => ({
            owner_id: owner,
            name: `Paged Person ${String(index).padStart(3, "0")}`,
          })),
        )
      ).error,
    ).toBeNull();
    await page
      .getByRole("link", { name: "Learning 学习 partner", exact: true })
      .click();
    await expect(page).toHaveURL(new RegExp(`/people\\?person=${person}$`));
    await page.getByRole("button", { name: /Learning 学习 partner/ }).click();
    await expect(
      page.getByRole("dialog").getByRole("textbox", { name: /^Notes/ }),
    ).toHaveValue("A standalone Person");
    await page
      .getByRole("dialog")
      .getByRole("button", { name: "Close Person editor", exact: true })
      .click();
    await page.goto("/search?q=" + encodeURIComponent("Paged Person"));
    const library = page.getByRole("region", {
      name: "People and Places",
      exact: true,
    });
    await expect(library).toContainText("105 matches");
    await expect(library.locator("article")).toHaveCount(20);
    await page
      .getByRole("link", { name: "Next library matches", exact: true })
      .click();
    await expect(page).toHaveURL(/libraryPage=2/);
    await expect(
      library.getByRole("link", { name: "Paged Person 020", exact: true }),
    ).toBeVisible();
    await page.goto(
      "/search?q=" + encodeURIComponent("学习") + "&type=standard",
    );
    await expect(
      page.getByText("Clear Entry filters to also search People and Places."),
    ).toBeVisible();
    await expect(library).toHaveCount(0);
    await page.goto("/search?q=" + encodeURIComponent("学习"));
    await page
      .getByRole("link", { name: "Learning 学习 library", exact: true })
      .click();
    await expect(page).toHaveURL(new RegExp(`/places\\?place=${place}$`));
    await expect(
      page.getByRole("button", { name: /Learning 学习 library/ }),
    ).toBeVisible();
    await page.goto("/search?q=" + encodeURIComponent("学习"));
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.screenshot({
      path: "/private/tmp/memotrail-library-keyword-mobile.png",
      fullPage: true,
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
    const response = await native.rpc("search_library_entities", {
      p_query: "学习",
      p_limit: 20,
      p_offset: 0,
    });
    expect(response.error).toBeNull();
    expect(response.data.total_count).toBe(3);
    expect(
      response.data.items.map((item: { kind: string }) => item.kind).sort(),
    ).toEqual(["habit", "person", "place"]);
    const webScope = await native.rpc("search_library_entities", {
      p_query: "学习",
      p_limit: 20,
      p_offset: 0,
      p_kinds: ["person", "place"],
    });
    expect(webScope.error).toBeNull();
    expect(webScope.data.total_count).toBe(2);
    expect(
      webScope.data.items.map((item: { kind: string }) => item.kind).sort(),
    ).toEqual(["person", "place"]);
    expect(
      (
        await client
          .from("people")
          .update({ deleted_at: new Date().toISOString() })
          .eq("id", person)
      ).error,
    ).toBeNull();
    await page.goto(`/people?person=${person}`);
    await expect(page.getByRole("main").getByRole("alert")).toContainText(
      "unavailable or in Trash",
    );
    await page.goto("/search?q=" + encodeURIComponent("学习"));
    await expect(
      page.getByRole("link", { name: "Learning 学习 partner", exact: true }),
    ).toHaveCount(0);
  } finally {
    await page.close();
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
