import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("Home previews the Inbox while Inbox remains a focused organization workspace", async ({
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
  const email = `home-inbox-${randomUUID()}@memotrail.local`;
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
      .insert(
        captures.map(([body, createdAt]) => ({
          body,
          created_at: createdAt,
          date_precision: "unknown",
          inbox_status: "unreviewed",
          item_kind: "entry",
          item_subtype: "entry",
          owner_id: owner,
          title: null,
        })),
      )
      .select("id,body");
    expect(inserted.error).toBeNull();
    const newestID = inserted.data?.find(
      (entry) => entry.body === "Newest thought",
    )?.id;
    expect(newestID).toBeTruthy();

    await page.goto("/");
    await expect(
      page.getByRole("form", { name: "Quick capture", exact: true }),
    ).toBeVisible();
    const ready = page.getByRole("region", { name: "Ready to organize" });
    await expect(
      page
        .getByRole("navigation", { name: "Primary navigation" })
        .getByRole("link", { name: "Inbox", exact: true }),
    ).toHaveCount(0);
    const inboxShortcut = page.getByRole("link", {
      name: "Open Inbox, 4 items",
      exact: true,
    });
    await expect(inboxShortcut).toBeVisible();
    await expect(inboxShortcut).toContainText("4");
    await expect(ready).toContainText("4 captures");
    await expect(ready.getByRole("link", { name: /Organize/ })).toHaveCount(3);
    await expect(
      ready.getByText("Newest thought", { exact: true }),
    ).toBeVisible();
    await expect(
      ready.getByText("Oldest thought", { exact: true }),
    ).toHaveCount(0);
    await expect(
      page.getByText("Waiting in Inbox", { exact: true }),
    ).toHaveCount(0);
    await expect(
      page.getByRole("link", {
        name: /0 Entries kept 0 First Times/,
      }),
    ).toBeVisible();
    await expect(
      page.getByRole("heading", { name: "Recent Entries", exact: true }),
    ).toBeVisible();
    await expect(page.getByText("Your trail starts here")).toBeVisible();
    await expect(
      page.getByRole("heading", { name: "Newest thought", exact: true }),
    ).toHaveCount(0);
    await expect(
      page.getByRole("textbox", { name: "Entry text" }),
    ).toBeEnabled();
    await page.screenshot({
      caret: "initial",
      fullPage: true,
      path: "/private/tmp/memotrail-home-inbox-preview.png",
    });

    await ready
      .getByRole("link", { name: "Organize Newest thought", exact: true })
      .click();
    await expect(page).toHaveURL(`/inbox?entry=${newestID}`);
    await expect(
      page.getByRole("dialog", { name: "Review Entry" }),
    ).toBeVisible();
    await expect(
      page.getByRole("form", { name: "Quick capture", exact: true }),
    ).toHaveCount(0);
    await page
      .getByRole("button", { name: "Close Inbox review", exact: true })
      .click();
    await expect(
      page.getByRole("heading", { name: "Ready to organize", exact: true }),
    ).toBeVisible();
    await expect(page.getByText("Quick capture", { exact: true })).toHaveCount(
      0,
    );
    await page.screenshot({
      caret: "initial",
      fullPage: true,
      path: "/private/tmp/memotrail-inbox-organize-only.png",
    });

    const oldestCard = page
      .locator("article")
      .filter({ hasText: "Oldest thought" });
    await oldestCard.getByRole("button", { name: "Move to Trash" }).click();
    const confirmation = page.getByRole("dialog", {
      name: /Move.*Trash/,
    });
    await expect(confirmation).toContainText("You can restore it later");
    await confirmation.getByRole("button", { name: "Cancel" }).click();
    await expect(oldestCard).toBeVisible();
    await oldestCard.getByRole("button", { name: "Move to Trash" }).click();
    await confirmation.getByRole("button", { name: "Move to Trash" }).click();
    await expect(oldestCard).toHaveCount(0);
    const deletedOldest = await client
      .from("entries")
      .select("deleted_at")
      .eq("body", "Oldest thought")
      .single();
    expect(deletedOldest.error).toBeNull();
    expect(deletedOldest.data!.deleted_at).not.toBeNull();

    await page.goto(`/inbox?entry=${newestID}`);
    const review = page.getByRole("dialog", { name: "Review Entry" });
    await expect(
      review.getByRole("button", { name: "Save changes" }),
    ).toHaveAttribute("data-variant", "secondary");
    await expect(
      review.getByRole("button", { name: "Save to Library" }),
    ).toHaveAttribute("data-variant", "primary");
    await page.setViewportSize({ width: 390, height: 844 });
    await expect(review).toBeVisible();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await page.screenshot({
      animations: "disabled",
      path: "/private/tmp/memotrail-inbox-review-mobile.png",
    });
    await review.getByRole("button", { name: "Move to Trash" }).click();
    await confirmation.getByRole("button", { name: "Move to Trash" }).click();
    await expect(review).toHaveCount(0);
    const deletedNewest = await client
      .from("entries")
      .select("deleted_at")
      .eq("id", newestID!)
      .single();
    expect(deletedNewest.error).toBeNull();
    expect(deletedNewest.data!.deleted_at).not.toBeNull();
  } finally {
    await admin.auth.admin.deleteUser(owner);
  }
});
