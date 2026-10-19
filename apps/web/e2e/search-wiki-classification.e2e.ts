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
  const harborChapter = randomUUID();

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
          id: harborChapter,
          title: "Marina flat",
          body: "Where I learned to sail.",
          item_kind: "entry",
          item_subtype: "chapter",
          date_precision: "unknown",
          owner_id: ownerID,
        })
      ).error,
    ).toBeNull();

    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    const visibleResult = (title: string) =>
      page.locator("[data-ui-entry-row]:visible").filter({
        has: page.locator("a:visible", { hasText: title }),
      });
    const show = page.getByRole("group", { name: "Show", exact: true });
    await page.goto("/search?type=entry&tag=Memory");
    await expect(show.getByRole("radio", { name: "Entries" })).toBeChecked();
    const tags = page.getByRole("button", { name: "Tags · 1", exact: true });
    await tags.click();
    await expect(
      page.getByRole("button", { name: "#Memory", exact: true }),
    ).toHaveAttribute("aria-pressed", "true");
    await expect(visibleResult("Marina memory")).toBeVisible();
    await expect(visibleResult("Marina memory")).toContainText("#Memory");
    await expect(
      visibleResult("Marina memory").locator("[data-mark]"),
    ).toHaveCount(0);
    await expect(visibleResult("Quiet reflection")).toHaveCount(0);

    // Links that filter by an older type still find the Chapter that replaced it.
    await page.goto("/search?q=marina&type=entity");
    await expect(show.getByRole("radio", { name: "Chapters" })).toBeChecked();
    await expect(visibleResult("Marina flat")).toBeVisible();
    await expect(
      visibleResult("Marina flat").getByRole("img", { name: "Chapter" }),
    ).toBeVisible();
    await expect(visibleResult("Marina memory")).toHaveCount(0);
    await show.getByText("Entries", { exact: true }).click();
    await expect(page).toHaveURL(/type=entry/);
    await expect(visibleResult("Marina memory")).toBeVisible();
    await expect(visibleResult("Marina flat")).toHaveCount(0);

    await page.waitForLoadState("networkidle");
    await show.getByRole("radio", { name: "Entries" }).press("Tab");
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
