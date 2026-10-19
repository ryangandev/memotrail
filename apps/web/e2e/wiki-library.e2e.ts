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

    const inserted = await client
      .from("entries")
      .insert([
        {
          body: "The quiet helped me notice what mattered.",
          item_kind: "entry",
          item_subtype: "entry",
          owner_id: ownerID,
          title: "Morning reflection",
        },
        {
          body: "A first glimpse of the Pacific.",
          item_kind: "entry",
          item_subtype: "entry",
          owner_id: ownerID,
          title: "Ocean memory",
        },
        {
          body: "Saved straight from the capture dock.",
          item_kind: "entry",
          item_subtype: "entry",
          owner_id: ownerID,
          title: "Fresh thought",
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
        await client.from("entries").insert({
          id: harborChapter,
          title: "Avery Street flat",
          body: "Lived by the marina.",
          item_kind: "entry",
          item_subtype: "chapter",
          date_precision: "unknown",
          owner_id: ownerID,
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
      path: test.info().outputPath("memotrail-library-default.png"),
    });
    await page.setViewportSize({ width: 390, height: 844 });
    await expect(
      page.getByRole("navigation", { name: "Mobile navigation" }),
    ).toBeVisible();
    // The search spans the column, and the filters scroll sideways inside it, not the page.
    await expect
      .poll(() =>
        page.evaluate(() => {
          const shown = (selector: string) =>
            [...document.querySelectorAll(selector)].find(
              (element) => element.getClientRects().length > 0,
            );
          const control = shown('[role="search"] [data-search-control]');
          const header = shown("[data-ui-page-header]");
          if (!control || !header) return Number.POSITIVE_INFINITY;
          return Math.abs(
            control.getBoundingClientRect().width -
              header.getBoundingClientRect().width,
          );
        }),
      )
      .toBeLessThanOrEqual(1);
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);
    await page.screenshot({
      animations: "disabled",
      caret: "initial",
      path: test.info().outputPath("memotrail-library-default-mobile.png"),
    });
    await page.setViewportSize({ width: 1280, height: 720 });
    await expect(
      page.getByRole("navigation", { name: "Library categories" }),
    ).toHaveCount(0);
    const show = page.getByRole("group", { name: "Show", exact: true });
    await expect(show.getByRole("radio", { name: "All" })).toBeChecked();
    await expect(show.getByRole("radio", { name: "People" })).toHaveCount(0);
    for (const name of ["Entries", "Chapters", "First Times"]) {
      await expect(show.getByRole("radio", { name })).toHaveCount(1);
    }
    await expect(
      page.getByRole("combobox", { name: "Collection" }),
    ).toHaveCount(0);
    const tagsButton = page.getByRole("button", { name: "Tags", exact: true });
    await expect(tagsButton).toHaveAttribute("aria-expanded", "false");
    await tagsButton.click();
    await expect(page.getByRole("group", { name: "Tags" })).toBeVisible();
    await tagsButton.click();
    await show.getByRole("radio", { name: "Chapters", exact: true }).click();
    await expect(page).toHaveURL(/type=chapter/);
    await expect(show.getByRole("radio", { name: "Chapters" })).toBeChecked();
    await expect(
      page.getByRole("main").getByText("1 Entry matches, newest first"),
    ).toBeVisible();
    for (const path of ["/people", `/people/${randomUUID()}`]) {
      await page.goto(path);
      await expect(page).toHaveURL(/\/library$/);
    }
    await expect(
      page.getByRole("navigation").getByRole("link", { name: "People" }),
    ).toHaveCount(0);
    await expect(
      page.getByText("More views and tools", { exact: true }),
    ).toHaveCount(0);
    const reflectionLink = page.getByRole("link", {
      name: /Morning reflection/,
    });
    await expect(reflectionLink).toBeVisible();
    await expect(reflectionLink).toHaveAttribute(
      "href",
      `/items/${reflectionID}`,
    );
    // A capture belongs to the Library as soon as it is saved.
    await expect(
      page.getByRole("link", { name: /Fresh thought/ }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: /Chapter.*Avery Street flat/ }),
    ).toBeVisible();
    await expect(
      page.getByRole("main").getByText("4 Entries, newest first"),
    ).toBeVisible();

    await page.goto("/library?q=Fresh");
    await expect(
      page.getByRole("main").getByText("1 Entry matches, best match first"),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: "Fresh thought", exact: true }),
    ).toBeVisible();
    await page.goto("/library");

    await reflectionLink.click();
    await expect(page).toHaveURL(`/items/${reflectionID}`);
    await expect(
      page.getByRole("heading", { name: "Morning reflection", exact: true }),
    ).toBeVisible();
    await expect(
      page.getByRole("article", { name: "Entry", exact: true }),
    ).toContainText("The calm helped me notice what mattered.");
    await expect(
      page.getByRole("link", { name: /version history/i }),
    ).toHaveCount(0);
    await expect(
      page.getByRole("button", { name: "Move to Trash" }),
    ).toBeVisible();
    await page.screenshot({
      caret: "initial",
      fullPage: true,
      path: test.info().outputPath("memotrail-wiki-item-detail-desktop.png"),
    });

    // Old version history links open the Item page.
    await page.goto(`/history?entry=${reflectionID}`);
    await expect(page).toHaveURL(new RegExp(`/items/${reflectionID}`));
    await expect(
      page.getByRole("heading", { name: "Morning reflection", exact: true }),
    ).toBeVisible();
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
      page.getByRole("link", { name: /Morning reflection/ }),
    ).toHaveCount(0);
    const trashedReflection = await client
      .from("entries")
      .select("deleted_at")
      .eq("id", reflectionID!)
      .single();
    expect(trashedReflection.error).toBeNull();
    expect(trashedReflection.data?.deleted_at).toBeTruthy();

    await show.getByRole("radio", { name: "Chapters", exact: true }).click();
    await expect(page).toHaveURL(/type=chapter/);
    await expect(
      page.getByRole("link", { name: /Avery Street flat/ }),
    ).toBeVisible();
    await expect(
      page.getByRole("link", { name: /Morning reflection/ }),
    ).toHaveCount(0);

    // Typing searches on its own, keeps the filters, and keeps the field focused.
    const search = page.getByRole("searchbox", { name: "Search Library" });
    await search.fill("marina");
    await expect(page).toHaveURL(/q=marina/);
    await expect(page).toHaveURL(/type=chapter/);
    await expect(search).toBeFocused();
    await show.getByRole("radio", { name: "All", exact: true }).click();
    await expect(page).not.toHaveURL(/type=/);
    await expect(search).toHaveValue("marina");
    await expect(
      page.getByRole("link", { name: /Avery Street flat/ }),
    ).toBeVisible();
    await page.waitForLoadState("networkidle");
    await search.press("Tab");

    await page.screenshot({
      caret: "initial",
      fullPage: true,
      path: test.info().outputPath("memotrail-wiki-library-desktop.png"),
    });
    await page.setViewportSize({ height: 844, width: 390 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.screenshot({
      caret: "initial",
      fullPage: true,
      path: test.info().outputPath("memotrail-wiki-library-mobile.png"),
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);

    const pageRows = Array.from({ length: 13 }, (_, index) => ({
      body: `A saved page item ${index + 1}.`,
      item_kind: "entry" as const,
      item_subtype: "entry",
      owner_id: ownerID,
      title: `Pagination item ${index + 1}`,
    }));
    expect((await client.from("entries").insert(pageRows)).error).toBeNull();
    await page.setViewportSize({ width: 1280, height: 720 });
    await page.goto("/library");
    const list = page.getByRole("region", { name: "Entries", exact: true });
    const pages = page.getByRole("navigation", { name: "Library pages" });
    await expect(list.getByRole("listitem")).toHaveCount(12);
    await expect(pages).toContainText("Page 1 of 2");
    await expect(
      pages.getByRole("button", { name: "Previous" }),
    ).toBeDisabled();
    await pages.getByRole("link", { name: "Next" }).click();
    await expect(page).toHaveURL(/\/library\?page=2$/);
    await expect(list.getByRole("listitem")).toHaveCount(4);
    await expect(pages).toContainText("Page 2 of 2");
    await expect(pages.getByRole("button", { name: "Next" })).toBeDisabled();
    await pages.getByRole("link", { name: "Previous" }).click();
    await expect(page).toHaveURL(/\/library$/);
    await expect(list.getByRole("listitem")).toHaveCount(12);
    await page.screenshot({
      animations: "disabled",
      caret: "initial",
      path: test.info().outputPath("memotrail-library-rows-desktop.png"),
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
      path: test.info().outputPath("memotrail-library-rows-mobile.png"),
    });
    await page.goto("/library?page=3");
    await expect(page).toHaveURL(/\/library$/);
    expect(errors).toEqual([]);
  } finally {
    await admin.auth.admin.deleteUser(ownerID);
  }
});
