import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import { fillOccurrenceStart } from "./helpers/occurrence";

test("Organization preserves relationships, Bucket List identity, and recoverable Collection deletion", async ({
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
  const email = `organization-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    password: randomUUID(),
    email_confirm: true,
  });
  if (!created.data.user)
    throw new Error("Could not create local test account.");
  const owner = created.data.user.id;
  try {
    const cookies: { name: string; value: string }[] = [];
    const client = createServerClient(env.API_URL, env.ANON_KEY, {
      cookies: {
        getAll: () => cookies,
        setAll: (values) => {
          for (const value of values)
            cookies.push({ name: value.name, value: value.value });
        },
      },
    });
    const link = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    if (!link.data.properties)
      throw new Error("Could not establish local fixture session.");
    expect(
      (
        await client.auth.verifyOtp({
          type: "magiclink",
          token_hash: link.data.properties.hashed_token,
        })
      ).error,
    ).toBeNull();
    await context.addCookies(
      cookies.map((cookie) => ({
        ...cookie,
        domain: "127.0.0.1",
        path: "/",
        httpOnly: false,
        sameSite: "Lax" as const,
      })),
    );
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    page.on("console", (message) => {
      if (message.type() === "error")
        errors.push(
          `${message.text()} (${message.location().url.split("?")[0]})`,
        );
    });

    await page.goto("/collections");
    await page
      .getByRole("link", { name: "Manage Collections and tags" })
      .click();
    await page
      .getByRole("button", { name: "Add Collection", exact: true })
      .click();
    const create = page.getByRole("form", { name: "New Collection" });
    await create.getByLabel("Name", { exact: true }).fill("Bucket List");
    await create.getByRole("button", { name: "Create Collection" }).click();
    const original = page.getByRole("form", {
      name: "Edit Bucket List",
      exact: true,
    });
    await expect(original).toBeVisible();
    const collection = await client
      .from("collections")
      .select("id")
      .eq("name", "Bucket List")
      .single();
    expect(collection.error).toBeNull();
    const collectionID = collection.data!.id;
    const entryID = randomUUID();
    expect(
      (
        await client.from("entries").insert({
          id: entryID,
          owner_id: owner,
          title: "Try pottery",
          body: "A personal reflection, not duplicated.",
          entry_type: "goal",
          inbox_status: "organized",
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("goals").insert({
          entry_id: entryID,
          owner_id: owner,
          horizon: "someday",
          status: "active",
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("entry_collections").insert({
          entry_id: entryID,
          owner_id: owner,
          collection_id: collectionID,
        })
      ).error,
    ).toBeNull();
    await page.reload();
    await expect(original).toContainText("1 Entry");
    await original
      .getByLabel("Name", { exact: true })
      .fill("Someday adventures");
    await original.getByLabel("Order", { exact: true }).fill("-10");
    await original.getByRole("button", { name: "Save changes" }).click();
    const renamed = page.getByRole("form", {
      name: "Edit Someday adventures",
      exact: true,
    });
    await expect(renamed).toContainText(
      "Renaming preserves its Goal milestone behavior.",
    );
    expect(
      (
        await client
          .from("entries")
          .select("revision")
          .eq("id", entryID)
          .single()
      ).data?.revision,
    ).toBe(2);
    await page.goto("/goals?entry=" + entryID);
    const goal = page.getByRole("dialog");
    await expect(
      goal.getByRole("button", { name: "Mark achieved and create First Time" }),
    ).toBeVisible();
    await goal
      .getByRole("combobox", { name: "Date type", exact: true })
      .selectOption("day");
    await fillOccurrenceStart(goal, "2026-09-12");
    const achievementResponse = page.waitForResponse(
      (response) =>
        response.request().method() === "POST" &&
        new URL(response.url()).pathname === "/goals",
    );
    await goal
      .getByRole("button", { name: "Mark achieved and create First Time" })
      .click();
    // A production RSC response can remain streaming after the mutation has settled.
    // Verify HTTP success, the visible confirmation, and persisted state rather than stream closure.
    expect((await achievementResponse).ok()).toBe(true);
    await expect(goal.getByRole("status")).toContainText(
      "Achievement saved, with a linked First Time.",
    );
    await expect
      .poll(
        async () =>
          (
            await client
              .from("goals")
              .select("status")
              .eq("entry_id", entryID)
              .single()
          ).data?.status,
      )
      .toBe("achieved");
    const linked = await client
      .from("entry_links")
      .select("target_entry_id")
      .eq("source_entry_id", entryID)
      .eq("relationship", "achievement")
      .single();
    expect(linked.error).toBeNull();
    expect(
      (
        await client
          .from("entries")
          .select("body")
          .eq("id", linked.data!.target_entry_id)
          .single()
      ).data?.body,
    ).toBe("");
    await page.goto("/settings/organization?kind=tag");
    await page.getByRole("button", { name: "Add tag", exact: true }).click();
    const newTag = page.getByRole("form", { name: "New tag" });
    await newTag.getByLabel("Name", { exact: true }).fill("ceramics");
    await newTag.getByRole("button", { name: "Create tag" }).click();
    await expect(
      page.getByRole("form", { name: "Edit ceramics", exact: true }),
    ).toBeVisible();
    const tag = await client
      .from("tags")
      .select("id")
      .eq("name", "ceramics")
      .single();
    expect(tag.error).toBeNull();
    expect(
      (
        await client
          .from("entry_tags")
          .insert({ entry_id: entryID, owner_id: owner, tag_id: tag.data!.id })
      ).error,
    ).toBeNull();
    await page.reload();
    const tagForm = page.getByRole("form", {
      name: "Edit ceramics",
      exact: true,
    });
    await tagForm.getByLabel("Name", { exact: true }).fill("陶艺");
    await tagForm.getByRole("button", { name: "Save changes" }).click();
    await expect(
      page.getByRole("form", { name: "Edit 陶艺", exact: true }),
    ).toContainText("1 Entry");
    await page.goto("/settings/organization");
    page.once("dialog", (d) => d.accept());
    await renamed.getByRole("button", { name: "Move to Trash" }).click();
    await expect(renamed).not.toBeVisible();
    await page.goto("/trash");
    await expect(
      page.getByText("Someday adventures", { exact: true }),
    ).toBeVisible();
    expect(
      (
        await client
          .from("entries")
          .select("deleted_at")
          .eq("id", entryID)
          .single()
      ).data?.deleted_at,
    ).toBeNull();
    // Reusing the name must not overwrite the removed grouping during restoration.
    expect(
      (
        await client.rpc("save_organization", {
          p_kind: "collection",
          p_name: "Someday adventures",
          p_sort_order: 0,
        })
      ).error,
    ).toBeNull();
    await page.getByRole("button", { name: "Restore", exact: true }).click();
    await expect(
      page.getByText(/An active Collection already has this name/),
    ).toBeVisible();
    await page.goto("/settings/organization");
    await renamed.getByLabel("Name", { exact: true }).fill("Travel ideas");
    await renamed.getByRole("button", { name: "Save changes" }).click();
    await expect(
      page.getByRole("form", { name: "Edit Travel ideas", exact: true }),
    ).toBeVisible();
    await page.goto("/trash");
    await page.getByRole("button", { name: "Restore", exact: true }).click();
    await expect(
      page.getByText("Someday adventures", { exact: true }),
    ).not.toBeVisible();
    await page.goto("/collections/" + collectionID);
    await expect(page.getByText("Try pottery", { exact: true })).toBeVisible();
    await page.goto("/settings/organization");
    await page.screenshot({
      path: "/private/tmp/memotrail-organization-desktop.png",
      caret: "initial",
      fullPage: true,
    });
    const current = await client
      .from("collections")
      .select("revision")
      .eq("id", collectionID)
      .single();
    expect(
      (
        await client.rpc("save_organization", {
          p_kind: "collection",
          p_name: "Someday adventures",
          p_sort_order: -20,
          p_id: collectionID,
          p_expected_revision: current.data!.revision,
        })
      ).error,
    ).toBeNull();
    await renamed.getByLabel("Name", { exact: true }).fill("Stale device");
    await renamed.getByRole("button", { name: "Save changes" }).click();
    await expect(renamed.getByRole("status")).toContainText(
      "changed on another device",
    );
    await page.getByRole("button", { name: "Reload items" }).click();
    await expect(renamed.getByLabel("Order", { exact: true })).toHaveValue(
      "-20",
    );
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.screenshot({
      path: "/private/tmp/memotrail-organization-mobile.png",
      caret: "initial",
      fullPage: true,
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    page.once("dialog", (d) => d.accept());
    await renamed.getByRole("button", { name: "Move to Trash" }).click();
    await expect(renamed).not.toBeVisible();
    await page.goto("/trash");
    await page
      .getByRole("button", { name: "Delete forever", exact: true })
      .click();
    await page
      .getByRole("dialog")
      .getByRole("button", { name: "Delete forever", exact: true })
      .click();
    await expect(
      page.getByText("Someday adventures", { exact: true }),
    ).not.toBeVisible();
    expect(
      (await client.from("entries").select("id").eq("id", entryID).single())
        .data?.id,
    ).toBe(entryID);
    expect(
      (
        await client
          .from("entry_tags")
          .select("tag_id")
          .eq("entry_id", entryID)
          .single()
      ).data?.tag_id,
    ).toBe(tag.data!.id);
    expect(errors).toEqual([]);
  } finally {
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
