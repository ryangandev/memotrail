import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("Library browses the complete Life Wiki by Kind and keyword", async ({
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
  const email = `wiki-library-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  if (!created.data.user) throw new Error("Local Library fixture unavailable.");
  const ownerID = created.data.user.id;

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

    const inserted = await client
      .from("entries")
      .insert([
        {
          body: "The quiet helped me notice what mattered.",
          inbox_status: "organized",
          item_kind: "writing",
          item_subtype: "reflection",
          owner_id: ownerID,
          title: "Morning reflection",
        },
        {
          body: "A first glimpse of the Pacific.",
          inbox_status: "organized",
          item_kind: "event",
          item_subtype: "memory",
          owner_id: ownerID,
          title: "Ocean memory",
        },
      ])
      .select("id,title");
    expect(inserted.error).toBeNull();
    const reflectionID = inserted.data?.find(
      (entry) => entry.title === "Morning reflection",
    )?.id;
    expect(reflectionID).toBeTruthy();
    expect(
      (
        await client
          .from("entries")
          .update({ body: "The calm helped me notice what mattered." })
          .eq("id", reflectionID!)
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("people").insert({
          name: "Avery",
          notes: "Met at the marina.",
          owner_id: ownerID,
          relationship_label: "Friend",
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("places").insert({
          city: "San Francisco",
          country: "USA",
          name: "Ocean Beach",
          notes: "Morning walks.",
          owner_id: ownerID,
        })
      ).error,
    ).toBeNull();

    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await page.goto("/library");
    await expect(page.getByRole("heading", { name: "Library" })).toBeVisible();
    const kinds = page.getByRole("navigation", { name: "Life Wiki Kinds" });
    const allItemsKind = kinds.getByRole("link", { name: "All items" });
    await expect(allItemsKind).toHaveAttribute("aria-current", "page");
    await expect(
      page.getByText("What each item is", { exact: true }),
    ).toHaveCount(0);
    await expect(allItemsKind.locator("p")).toHaveCount(0);
    await expect(
      kinds.getByText("Journal, reflection, or lesson."),
    ).toBeVisible();
    await expect
      .poll(async () => (await allItemsKind.boundingBox())?.height)
      .toBeLessThanOrEqual(100);
    await expect(kinds.getByRole("link", { name: /Writing/ })).toBeVisible();
    await expect(kinds.getByRole("link", { name: /Entities/ })).toBeVisible();
    await expect(
      page.getByRole("heading", { name: "Focused views", exact: true }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: /Version history/ }),
    ).toBeVisible();
    const reflectionLink = page.getByRole("link", {
      name: /Writing Reflection Morning reflection/,
    });
    await expect(reflectionLink).toBeVisible();
    await expect(reflectionLink).toHaveAttribute(
      "href",
      `/items/${reflectionID}`,
    );
    await expect(
      page.getByRole("link", { name: /Entity Person Avery/ }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: /Entity Place Ocean Beach/ }),
    ).toBeVisible();
    await expect(
      page.getByRole("main").getByText("4 items", { exact: true }),
    ).toBeVisible();

    await reflectionLink.click();
    await expect(page).toHaveURL(`/items/${reflectionID}`);
    await expect(
      page.getByRole("heading", { name: "Morning reflection", exact: true }),
    ).toBeVisible();
    await expect(
      page.getByRole("article", { name: "Current item" }),
    ).toContainText("The calm helped me notice what mattered.");
    await expect(
      page.getByRole("link", { name: "View version history (1)" }),
    ).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Move to Trash" }),
    ).toBeVisible();
    await page.screenshot({
      caret: "initial",
      fullPage: true,
      path: "/private/tmp/memotrail-wiki-item-detail-desktop.png",
    });

    await page.getByRole("link", { name: "View version history (1)" }).click();
    await expect(page).toHaveURL(`/history?entry=${reflectionID}`);
    await expect(
      page.getByRole("heading", { name: "Version history", exact: true }),
    ).toBeVisible();
    await expect(
      page.getByRole("region", { name: "Earlier version" }),
    ).toContainText("The quiet helped me notice what mattered.");

    await page.goto(`/items/${reflectionID}`);
    page.once("dialog", (dialog) => dialog.accept());
    await page.getByRole("button", { name: "Move to Trash" }).click();
    await expect(page).toHaveURL(/\/library$/);
    await expect(
      page.getByRole("link", { name: /Writing Reflection Morning reflection/ }),
    ).toHaveCount(0);
    const trashedReflection = await client
      .from("entries")
      .select("deleted_at")
      .eq("id", reflectionID!)
      .single();
    expect(trashedReflection.error).toBeNull();
    expect(trashedReflection.data?.deleted_at).toBeTruthy();

    const filters = page.locator('form:visible:has(select[name="kind"])');
    await filters.locator('select[name="kind"]').selectOption("entity");
    await filters.getByRole("button", { name: "Apply" }).click();
    await expect(page).toHaveURL(/kind=entity/);
    await expect(
      page.getByRole("link", { name: /Entity Person Avery/ }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: /Entity Place Ocean Beach/ }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: /Writing Reflection Morning reflection/ }),
    ).toHaveCount(0);

    await filters.locator('select[name="kind"]').selectOption("");
    await filters.locator('input[name="q"]').fill("marina");
    await filters.getByRole("button", { name: "Apply" }).click();
    await expect(
      page.getByRole("link", { name: /Entity Person Avery/ }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: /Entity Place Ocean Beach/ }),
    ).toHaveCount(0);
    await page.waitForLoadState("networkidle");
    await filters.locator('input[name="q"]').press("Tab");

    await page.screenshot({
      caret: "initial",
      fullPage: true,
      path: "/private/tmp/memotrail-wiki-library-desktop.png",
    });
    await page.setViewportSize({ height: 844, width: 390 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.screenshot({
      caret: "initial",
      fullPage: true,
      path: "/private/tmp/memotrail-wiki-library-mobile.png",
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
