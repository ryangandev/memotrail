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
          item_kind: "entry",
          item_subtype: "entry",
          owner_id: ownerID,
          title: "Morning reflection",
        },
        {
          body: "A first glimpse of the Pacific.",
          inbox_status: "organized",
          item_kind: "entry",
          item_subtype: "entry",
          owner_id: ownerID,
          title: "Ocean memory",
        },
        {
          body: "Only saved to Inbox so far.",
          inbox_status: "unreviewed",
          item_kind: "entry",
          item_subtype: "entry",
          owner_id: ownerID,
          title: "Inbox-only thought",
        },
      ])
      .select("id,title");
    expect(inserted.error).toBeNull();
    const reflectionID = inserted.data?.find(
      (entry) => entry.title === "Morning reflection",
    )?.id;
    const inboxOnlyID = inserted.data?.find(
      (entry) => entry.title === "Inbox-only thought",
    )?.id;
    expect(reflectionID).toBeTruthy();
    expect(inboxOnlyID).toBeTruthy();
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

    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await page.goto("/library");
    await expect(
      page.getByRole("heading", { name: "Library", exact: true }),
    ).toBeVisible();
    await page.screenshot({
      animations: "disabled",
      caret: "initial",
      path: "/private/tmp/memotrail-library-default.png",
    });
    await page.setViewportSize({ width: 390, height: 844 });
    await expect(
      page.getByRole("navigation", { name: "Mobile navigation" }),
    ).toBeVisible();
    await page.screenshot({
      animations: "disabled",
      caret: "initial",
      path: "/private/tmp/memotrail-library-default-mobile.png",
    });
    await page.setViewportSize({ width: 1280, height: 720 });
    await expect(
      page.getByRole("navigation", { name: "Library categories" }),
    ).toHaveCount(0);
    await page.getByText("Filters", { exact: true }).click();
    const showFilter = page.getByRole("combobox", { name: "Record" });
    await expect(showFilter).toHaveValue("");
    await showFilter.selectOption("entity");
    await page.getByRole("button", { name: "Search", exact: true }).click();
    await expect(page).toHaveURL(/type=entity/);
    await expect(page.getByRole("heading", { name: "Results" })).toBeVisible();
    await page.goto("/library");
    await page.getByText("More views and tools", { exact: true }).click();
    await expect(
      page.getByRole("navigation", { name: "Focused views" }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: "Places", exact: true }),
    ).toHaveCount(0);
    await expect(
      page.getByRole("link", { name: /Version history/ }),
    ).toBeVisible();
    const reflectionLink = page.getByRole("link", {
      name: /Entry.*Morning reflection/,
    });
    await expect(reflectionLink).toBeVisible();
    await expect(reflectionLink).toHaveAttribute(
      "href",
      `/items/${reflectionID}`,
    );
    await expect(
      page.getByRole("link", { name: /Entry.*Inbox-only thought/ }),
    ).toHaveCount(0);
    await expect(
      page.getByRole("link", { name: /Entity.*Person.*Avery/ }),
    ).toBeVisible();
    await expect(
      page.getByRole("main").getByText("3 items", { exact: true }),
    ).toBeVisible();

    await page.goto("/library?q=Inbox-only");
    await expect(
      page.getByRole("main").getByText("1 item", { exact: true }),
    ).toBeVisible();
    await expect(page.getByText("In Inbox", { exact: true })).toBeVisible();
    await page.goto(`/inbox?entry=${inboxOnlyID}`);
    const inboxReview = page.getByRole("dialog", { name: "Review Entry" });
    await expect(inboxReview).toBeVisible();
    await inboxReview.getByRole("button", { name: "Save to Library" }).click();
    await expect(inboxReview).toHaveCount(0);
    await page.goto("/library");
    await expect(
      page.getByRole("link", { name: /Entry.*Inbox-only thought/ }),
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
    await page.getByRole("button", { name: "Move to Trash" }).click();
    await page
      .getByRole("dialog", {
        name: "Move “Morning reflection” to Trash?",
        exact: true,
      })
      .getByRole("button", { name: "Move to Trash", exact: true })
      .click();
    await expect(page).toHaveURL(/\/library$/);
    await expect(
      page.locator("[data-sonner-toast]").filter({
        hasText: "Entry moved to Trash.",
      }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: /Entry.*Morning reflection/ }),
    ).toHaveCount(0);
    const trashedReflection = await client
      .from("entries")
      .select("deleted_at")
      .eq("id", reflectionID!)
      .single();
    expect(trashedReflection.error).toBeNull();
    expect(trashedReflection.data?.deleted_at).toBeTruthy();

    await page.getByText("Filters", { exact: true }).click();
    const filters = page.locator('form:visible:has(select[name="type"])');
    await filters.locator('select[name="type"]').selectOption("entity");
    await filters.getByRole("button", { name: "Search", exact: true }).click();
    await expect(page).toHaveURL(/type=entity/);
    await expect(
      page.getByRole("link", { name: "Avery", exact: true }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: /Writing Reflection Morning reflection/ }),
    ).toHaveCount(0);

    await filters.locator('select[name="type"]').selectOption("");
    await filters.locator('input[name="q"]').fill("marina");
    await filters.getByRole("button", { name: "Search", exact: true }).click();
    await expect(
      page.getByRole("link", { name: "Avery", exact: true }),
    ).toBeVisible();
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

    const pageRows = Array.from({ length: 13 }, (_, index) => ({
      body: `A saved page item ${index + 1}.`,
      inbox_status: "organized" as const,
      item_kind: "entry" as const,
      item_subtype: "entry",
      owner_id: ownerID,
      title: `Pagination item ${index + 1}`,
    }));
    expect((await client.from("entries").insert(pageRows)).error).toBeNull();
    await page.setViewportSize({ width: 1280, height: 720 });
    await page.goto("/library");
    const list = page.getByRole("list", { name: "Library items" });
    const pages = page.getByRole("navigation", { name: "Life Wiki pages" });
    await expect(list.getByRole("listitem")).toHaveCount(12);
    await expect(pages).toContainText("Page 1 of 2");
    await pages.getByRole("link", { name: "Next" }).click();
    await expect(page).toHaveURL(/\/library\?page=2$/);
    await expect(list.getByRole("listitem")).toHaveCount(4);
    await expect(pages).toContainText("Page 2 of 2");
    await pages.getByRole("link", { name: "Previous" }).click();
    await expect(page).toHaveURL(/\/library$/);
    await expect(list.getByRole("listitem")).toHaveCount(12);
    await page.screenshot({
      animations: "disabled",
      caret: "initial",
      path: "/private/tmp/memotrail-library-rows-desktop.png",
    });
    await page.setViewportSize({ width: 390, height: 844 });
    await expect
      .poll(() =>
        page.evaluate(
          () => document.documentElement.scrollWidth <= window.innerWidth,
        ),
      )
      .toBe(true);
    await page.screenshot({
      animations: "disabled",
      caret: "initial",
      path: "/private/tmp/memotrail-library-rows-mobile.png",
    });
    await page.goto("/library?page=3");
    await expect(page).toHaveURL(/\/library$/);
    expect(errors).toEqual([]);
  } finally {
    await admin.auth.admin.deleteUser(ownerID);
  }
});
