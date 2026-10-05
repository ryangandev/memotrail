import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("captures land in Library and wait under Needs organizing until they have a place", async ({
  context,
  page,
}) => {
  const env = JSON.parse(
    execFileSync("supabase", ["status", "-o", "json"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }),
  );
  const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
  const email = `needs-organizing-${randomUUID()}@memotrail.local`;
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
    await client.auth.verifyOtp({
      type: "magiclink",
      token_hash: link.data.properties!.hashed_token,
    });
    await context.addCookies(
      cookies.map((cookie) => ({
        ...cookie,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax" as const,
      })),
    );

    const profile = await client
      .from("profiles")
      .update({ display_name: "Test User" })
      .eq("user_id", owner);
    expect(profile.error).toBeNull();

    const captures = [
      ["Oldest thought", "2026-09-14T08:00:00Z"],
      ["Third newest thought", "2026-09-15T08:00:00Z"],
      ["Second newest thought", "2026-09-16T08:00:00Z"],
      ["Newest thought", "2026-09-17T08:00:00Z"],
    ] as const;
    const inserted = await client
      .from("entries")
      .insert([
        ...captures.map(([body, createdAt]) => ({
          body,
          created_at: createdAt,
          updated_at: createdAt,
          date_precision: "unknown",
          item_kind: "entry",
          item_subtype: "entry",
          owner_id: owner,
          title: null,
        })),
        {
          body: "Already has a place.",
          created_at: "2026-09-10T08:00:00Z",
          updated_at: "2026-09-10T08:00:00Z",
          date_precision: "unknown",
          item_kind: "entry",
          item_subtype: "entry",
          owner_id: owner,
          title: "A titled memory",
        },
      ])
      .select("id,body");
    expect(inserted.error).toBeNull();
    const idFor = (body: string) =>
      inserted.data!.find((entry) => entry.body === body)!.id;
    const newestID = idFor("Newest thought");
    const oldestID = idFor("Oldest thought");

    await page.goto("/");
    await expect(
      page.getByRole("form", { name: "Quick capture", exact: true }),
    ).toBeVisible();
    await expect(page.getByRole("link", { name: /Inbox/ })).toHaveCount(0);
    const needsOrganizing = page.getByRole("region", {
      name: "Needs organizing",
    });
    await expect(
      needsOrganizing.getByRole("link", { name: "Library · 4" }),
    ).toHaveAttribute("href", "/library?show=needs-organizing");
    await expect(
      needsOrganizing.getByRole("link", { name: /^Organize / }),
    ).toHaveCount(3);
    await expect(
      needsOrganizing.getByText("Newest thought", { exact: true }),
    ).toBeVisible();
    await expect(
      needsOrganizing.getByText("Oldest thought", { exact: true }),
    ).toHaveCount(0);
    await expect(
      page.getByRole("link", { name: "4 To organize" }),
    ).toHaveAttribute("href", "/library?show=needs-organizing");
    await expect(
      page.getByRole("link", { name: "5 Entries kept" }),
    ).toBeVisible();
    await expect(
      page
        .getByRole("region", { name: "Recent Entries", exact: true })
        .getByText("Newest thought", { exact: true }),
    ).toBeVisible();
    await page.screenshot({
      caret: "initial",
      fullPage: true,
      path: "/private/tmp/memotrail-home-needs-organizing.png",
    });

    await needsOrganizing
      .getByRole("link", { name: "Organize Newest thought", exact: true })
      .click();
    await expect(page).toHaveURL(`/items/${newestID}`);
    await page.getByRole("button", { name: "Edit Entry", exact: true }).click();
    const editor = page.getByRole("dialog", { name: "Edit Entry" });
    await expect(editor.getByRole("textbox", { name: "Title" })).toBeFocused();
    await expect(
      editor.getByRole("button", { name: "Save to Library" }),
    ).toHaveCount(0);
    await expect(
      editor.getByRole("button", { name: "Save changes" }),
    ).toHaveAttribute("data-variant", "primary");
    await expect(
      editor.getByRole("button", { name: "Cancel", exact: true }),
    ).toHaveAttribute("data-variant", "secondary");
    const tags = editor.getByRole("group", { name: "Tags", exact: true });
    const photos = editor.getByRole("region", {
      name: "Photo date suggestions",
    });
    expect(
      await tags.evaluate(
        (element, photoElement) =>
          Boolean(
            element.compareDocumentPosition(photoElement as Node) &
            Node.DOCUMENT_POSITION_FOLLOWING,
          ),
        await photos.elementHandle(),
      ),
    ).toBe(true);
    await page.screenshot({
      animations: "disabled",
      caret: "hide",
      path: "/private/tmp/memotrail-entry-editor.png",
    });
    await editor
      .getByRole("textbox", { name: "Title" })
      .fill("The newest thought, sorted");
    await editor.getByRole("button", { name: "Save changes" }).click();
    await expect(editor).toHaveCount(0);
    await expect(
      page.locator("[data-sonner-toast]").filter({ hasText: "Entry saved." }),
    ).toBeVisible();
    // The save finishes once the Item page shows the new title.
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(
      "The newest thought, sorted",
    );

    await page.goto("/library");
    const library = page.getByRole("region", { name: "All items" });
    await expect(library.getByText("5 items", { exact: true })).toBeVisible();
    await library
      .getByRole("link", { name: "3 need organizing", exact: true })
      .click();
    await expect(page).toHaveURL("/library?show=needs-organizing");
    const list = page.getByRole("region", { name: "Needs organizing" });
    await expect(list.getByText("3 items", { exact: true })).toBeVisible();
    await expect(
      list.getByRole("list", { name: "Library items" }).getByRole("listitem"),
    ).toHaveCount(3);
    await expect(
      list.getByText("The newest thought, sorted", { exact: true }),
    ).toHaveCount(0);
    await expect(
      list.getByText("A titled memory", { exact: true }),
    ).toHaveCount(0);
    await page.setViewportSize({ width: 390, height: 844 });
    await expect
      .poll(() =>
        page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
      )
      .toBe(true);
    const mobileNavigation = page.getByRole("navigation", {
      name: "Mobile navigation",
    });
    await expect(
      mobileNavigation.getByRole("link", { name: "Map", exact: true }),
    ).toBeVisible();
    await expect(
      mobileNavigation.getByRole("link", { name: /Inbox/ }),
    ).toHaveCount(0);
    await page.screenshot({
      animations: "disabled",
      fullPage: true,
      path: "/private/tmp/memotrail-library-needs-organizing-mobile.png",
    });
    await list
      .getByRole("link", { name: "Show all items", exact: true })
      .click();
    await expect(page).toHaveURL("/library");

    // Links saved before Inbox was retired still open the right place.
    await page.goto("/inbox");
    await expect(page).toHaveURL("/library?show=needs-organizing");
    await page.goto(`/inbox?entry=${oldestID}`);
    await expect(page).toHaveURL(new RegExp(`/items/${oldestID}`));
  } finally {
    await admin.auth.admin.deleteUser(owner);
  }
});
