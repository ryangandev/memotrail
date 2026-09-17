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
          item_kind: "capture",
          item_subtype: "quick_capture",
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
      page.getByText("Entries kept", { exact: true }).locator(".."),
    ).toContainText("0");
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
      fullPage: true,
      path: "/private/tmp/memotrail-home-inbox-preview.png",
    });

    await ready
      .getByRole("link", { name: "Organize Newest thought", exact: true })
      .click();
    await expect(page).toHaveURL(`/inbox?entry=${newestID}`);
    await expect(
      page.getByRole("dialog", { name: "Organize Capture" }),
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
      fullPage: true,
      path: "/private/tmp/memotrail-inbox-organize-only.png",
    });
  } finally {
    await admin.auth.admin.deleteUser(owner);
  }
});
