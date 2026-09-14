import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";
import { fillOccurrenceStart } from "./helpers/occurrence";

test("Collections and Tags are first-class and organize generic Timeline moments", async ({
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
  const email = `organization-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
    password: randomUUID(),
  });
  if (!created.data.user) throw new Error("Could not create local test account.");
  const owner = created.data.user.id;

  try {
    const cookies: { name: string; value: string }[] = [];
    const client = createServerClient(env.API_URL, env.ANON_KEY, {
      cookies: {
        getAll: () => cookies,
        setAll: (values) => {
          for (const value of values) {
            cookies.push({ name: value.name, value: value.value });
          }
        },
      },
    });
    const link = await admin.auth.admin.generateLink({ type: "magiclink", email });
    if (!link.data.properties) {
      throw new Error("Could not establish local fixture session.");
    }
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
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    page.on("console", (message) => {
      if (message.type() === "error") errors.push(message.text());
    });

    await page.goto("/collections");
    await expect(page.getByRole("heading", { name: "Collections" })).toBeVisible();
    await expect(
      page.getByRole("navigation", { name: "Archive organization" }),
    ).toHaveCount(0);
    await page.getByRole("button", { name: "New Collection" }).click();
    const collectionDialog = page.getByRole("dialog", {
      name: "Create a Collection",
    });
    await collectionDialog.getByLabel("Name *").fill("City chapters");
    await collectionDialog.getByLabel("Display order *").fill("-10");
    await collectionDialog
      .getByRole("button", { name: "Create Collection" })
      .click();
    await expect(collectionDialog).not.toBeVisible();
    await expect(page.getByRole("heading", { name: "City chapters" })).toBeVisible();

    await page
      .getByRole("navigation", { name: "Primary navigation" })
      .getByRole("link", { name: "Tags", exact: true })
      .click();
    await expect(page).toHaveURL(/\/tags$/);
    await expect(
      page.getByRole("navigation", { name: "Archive organization" }),
    ).toHaveCount(0);
    for (const name of ["travel", "journeys", "unused"]) {
      await page.getByRole("button", { name: "New Tag" }).click();
      const tagDialog = page.getByRole("dialog", { name: "Create a Tag" });
      await tagDialog.getByLabel("Name *").fill(name);
      await tagDialog.getByRole("button", { name: "Create Tag" }).click();
      await expect(tagDialog).not.toBeVisible();
      await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
    }

    await page.goto("/timeline");
    const birthDatePrompt = page.getByRole("dialog", {
      name: "When did your story begin?",
    });
    if (await birthDatePrompt.isVisible()) {
      await expect(birthDatePrompt).toHaveAttribute("data-hydrated", "true");
      await birthDatePrompt
        .getByRole("button", { name: "Not now", exact: true })
        .click();
      await expect(birthDatePrompt).not.toBeVisible();
    }
    await page.getByRole("button", { name: "Add moment", exact: true }).click();
    await page
      .getByRole("dialog", { name: "What are you adding?" })
      .getByRole("button", { name: "Add Moment", exact: true })
      .click();
    const momentDialog = page.getByRole("dialog", { name: "Add to your story" });
    await momentDialog.getByLabel("Title", { exact: true }).fill("Moved to Seattle");
    await momentDialog
      .getByRole("combobox", { name: "Date type", exact: true })
      .selectOption("day");
    await fillOccurrenceStart(momentDialog, "2025-03-14");
    await momentDialog.getByLabel("Add a Collection").fill("City chapters");
    await momentDialog.getByLabel("Add a Collection").press("Enter");
    await momentDialog.getByLabel("Add a tag").fill("travel");
    await momentDialog.getByLabel("Add a tag").press("Enter");
    await momentDialog.getByRole("button", { name: "Add moment" }).click();
    await expect(momentDialog).not.toBeVisible();

    const entry = await client
      .from("entries")
      .select("id")
      .eq("owner_id", owner)
      .eq("title", "Moved to Seattle")
      .single();
    expect(entry.error).toBeNull();
    expect(
      (
        await client
          .from("entry_collections")
          .select("collection_id", { count: "exact", head: true })
          .eq("entry_id", entry.data!.id)
      ).count,
    ).toBe(1);
    expect(
      (
        await client
          .from("entry_tags")
          .select("tag_id", { count: "exact", head: true })
          .eq("entry_id", entry.data!.id)
      ).count,
    ).toBe(1);

    await page.goto("/tags");
    const travelRow = page.getByRole("article").filter({ hasText: "travel" });
    await expect(travelRow).toContainText("Used by 1 Entry");
    await travelRow.getByRole("button", { name: "Edit travel" }).click();
    const travelDialog = page.getByRole("dialog", { name: "travel" });
    await travelDialog
      .getByLabel("Destination tag")
      .selectOption({ label: "#journeys (0)" });
    page.once("dialog", (dialog) => dialog.accept());
    await travelDialog.getByRole("button", { name: "Merge tag" }).click();
    await expect(travelDialog).not.toBeVisible();
    await expect(page.getByRole("heading", { name: "travel", exact: true })).toHaveCount(0);
    await expect(page.getByRole("article").filter({ hasText: "journeys" })).toContainText(
      "Used by 1 Entry",
    );

    const unusedRow = page.getByRole("article").filter({ hasText: "unused" });
    await unusedRow.getByRole("button", { name: "Edit unused" }).click();
    const unusedDialog = page.getByRole("dialog", { name: "unused" });
    page.once("dialog", (dialog) => dialog.accept());
    await unusedDialog.getByRole("button", { name: "Delete unused tag" }).click();
    await expect(unusedDialog).not.toBeVisible();
    await expect(page.getByRole("heading", { name: "unused", exact: true })).toHaveCount(0);

    await page.goto("/settings/organization?kind=tag");
    await expect(page).toHaveURL(/\/tags$/);
    await page.screenshot({
      caret: "initial",
      fullPage: true,
      path: "/private/tmp/memotrail-tags-desktop.png",
    });
    await page.setViewportSize({ height: 844, width: 390 });
    await page.screenshot({
      caret: "initial",
      fullPage: true,
      path: "/private/tmp/memotrail-tags-mobile.png",
    });
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
    ).toBe(true);
    expect(errors).toEqual([]);
  } finally {
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
