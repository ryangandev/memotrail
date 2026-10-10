import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("Search filters Entries by record and descriptive tag", async ({
  context,
  page,
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
  const email = `semantic-search-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  if (!created.data.user) throw new Error("Local Search fixture unavailable.");
  const ownerID = created.data.user.id;
  const harborHome = randomUUID();

  try {
    const cookies: { name: string; value: string }[] = [];
    const client = createServerClient(env.API_URL, env.ANON_KEY, {
      cookies: {
        getAll: () => cookies,
        setAll: (values) => {
          cookies.push(
            ...values.map((value) => ({
              name: value.name,
              value: value.value,
            })),
          );
        },
      },
    });
    const link = await admin.auth.admin.generateLink({
      email,
      type: "magiclink",
    });
    if (!link.data.properties) throw new Error("Local sign-in unavailable.");
    expect(
      (
        await client.auth.verifyOtp({
          token_hash: link.data.properties.hashed_token,
          type: "magiclink",
        })
      ).error,
    ).toBeNull();
    await context.addCookies(
      cookies.map((cookie) => ({
        ...cookie,
        domain: "127.0.0.1",
        httpOnly: false,
        path: "/",
        sameSite: "Lax" as const,
      })),
    );

    expect(
      (
        await client
          .from("entries")
          .insert([
            {
              body: "I noticed how quiet the room felt.",
              item_kind: "entry",
              item_subtype: "entry",
              owner_id: ownerID,
              title: "Quiet reflection",
            },
            {
              body: "A very good day at the water.",
              item_kind: "entry",
              item_subtype: "entry",
              owner_id: ownerID,
              title: "Marina memory",
            },
          ])
          .select("id,title")
      ).error,
    ).toBeNull();
    const memory = await client
      .from("entries")
      .select("id")
      .eq("owner_id", ownerID)
      .eq("title", "Marina memory")
      .single();
    expect(memory.data?.id).toBeTruthy();
    const tag = await client
      .from("tags")
      .insert({ name: "Memory", owner_id: ownerID })
      .select("id")
      .single();
    expect(tag.data?.id).toBeTruthy();
    expect(
      (
        await client.from("entry_tags").insert({
          entry_id: memory.data!.id,
          owner_id: ownerID,
          tag_id: tag.data!.id,
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("entries").insert({
          id: harborHome,
          title: "Marina flat",
          body: "Where I learned to sail.",
          item_kind: "entity",
          item_subtype: "home",
          date_precision: "unknown",
          owner_id: ownerID,
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client
          .from("homes")
          .insert({ entry_id: harborHome, owner_id: ownerID })
      ).error,
    ).toBeNull();

    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    const visibleResult = (title: string) =>
      page.locator("article:visible").filter({
        has: page.locator("a:visible", { hasText: title }),
      });
    await page.goto("/search?type=entry&tag=Memory");
    await expect(page.getByLabel("Record")).toHaveValue("entry");
    await expect(page.getByLabel("Tag")).toHaveValue("Memory");
    await expect(visibleResult("Marina memory")).toBeVisible();
    await expect(visibleResult("Marina memory")).toContainText("Entry");
    await expect(visibleResult("Quiet reflection")).toHaveCount(0);

    await page.goto("/search?q=marina&type=entity");
    await expect(visibleResult("Marina flat")).toBeVisible();
    await page.getByLabel("Record").selectOption("home");
    await page.getByRole("button", { name: "Search", exact: true }).click();
    await expect(page).toHaveURL(/type=home/);
    await expect(visibleResult("Marina flat")).toBeVisible();

    await page.waitForLoadState("networkidle");
    await page.getByLabel("Record").press("Tab");
    await page.screenshot({
      caret: "initial",
      fullPage: true,
      path: test.info().outputPath("memotrail-semantic-search-desktop.png"),
    });
    await page.setViewportSize({ height: 844, width: 390 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.screenshot({
      caret: "initial",
      fullPage: true,
      path: test.info().outputPath("memotrail-semantic-search-mobile.png"),
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);
    expect(errors).toEqual([]);
  } finally {
    await admin.auth.admin.deleteUser(ownerID);
  }
});
