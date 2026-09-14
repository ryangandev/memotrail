import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("Timeline tracks create, rename, reorder, hide and reveal moments with revision protection", async ({
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
  const email = `tracks-${randomUUID()}@memotrail.local`;
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
    expect(
      (
        await client
          .from("profiles")
          .update({ birth_date: "1990-01-01" })
          .eq("user_id", owner)
      ).error,
    ).toBeNull();
    await page.goto("/timeline");
    await page.getByRole("link", { name: "Manage tracks" }).click();
    await page.getByRole("button", { name: "Add track", exact: true }).click();
    const form = page.getByRole("form", { name: "New track" });
    await form.getByLabel("Name", { exact: true }).fill("Creative practice");
    await form.getByLabel("Order", { exact: true }).fill("-100");
    await form.getByRole("button", { name: "Create track" }).click();
    const card = page.getByRole("form", {
      name: "Edit Creative practice",
      exact: true,
    });
    await expect(card).toBeVisible();
    expect(
      await page
        .getByRole("form", { name: /^Edit / })
        .first()
        .getAttribute("aria-label"),
    ).toBe("Edit Creative practice");
    const track = await client
      .from("timeline_tracks")
      .select("id,revision")
      .eq("name", "Creative practice")
      .single();
    expect(track.error).toBeNull();
    const id = track.data!.id;
    const entryID = randomUUID();
    expect(
      (
        await client.from("entries").insert({
          id: entryID,
          owner_id: owner,
          title: "First pottery class",
          body: "Learning to shape a bowl.",
          occurred_start: "2026-09-01T12:00:00Z",
          date_precision: "day",
          occurred_timezone: "UTC",
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("timeline_items").insert({
          owner_id: owner,
          entry_id: entryID,
          track_id: id,
          timeline_kind: "event",
        })
      ).error,
    ).toBeNull();
    await page.reload();
    await expect(card).toContainText("1 moment");
    await card.getByLabel("Hide from Timeline").check();
    await card.getByRole("button", { name: "Save track" }).click();
    await expect(card).toContainText("Hidden");
    await page.goto("/timeline");
    await expect(
      page.getByText("First pottery class", { exact: true }),
    ).toHaveCount(0);
    expect(
      (
        await client
          .from("entries")
          .select("deleted_at")
          .eq("id", entryID)
          .single()
      ).data?.deleted_at,
    ).toBeNull();
    await page.goto("/timeline/tracks");
    await card.getByLabel("Hide from Timeline").uncheck();
    await card.getByLabel("Name", { exact: true }).fill("Art & learning");
    await card.getByRole("button", { name: "Save track" }).click();
    const renamed = page.getByRole("form", {
      name: "Edit Art & learning",
      exact: true,
    });
    await expect(renamed).toBeVisible();
    await page.screenshot({
      path: "/private/tmp/memotrail-tracks-desktop.png",
      fullPage: true,
    });
    await page.goto("/timeline");
    await expect(
      page.getByText("First pottery class", { exact: true }).first(),
    ).toBeVisible();
    await page.goto("/timeline/tracks");
    // Simulate a different device while the visible form still holds revision 3.
    expect(
      (
        await client.rpc("save_timeline_track", {
          p_name: "Art & learning",
          p_sort_order: -90,
          p_is_hidden: false,
          p_track_id: id,
          p_expected_revision: 3,
        })
      ).error,
    ).toBeNull();
    await renamed.getByLabel("Name", { exact: true }).fill("Stale overwrite");
    await renamed.getByRole("button", { name: "Save track" }).click();
    await expect(renamed.getByRole("status")).toContainText(
      "changed on another device",
    );
    await page.getByRole("button", { name: "Reload tracks" }).click();
    await expect(renamed.getByLabel("Order", { exact: true })).toHaveValue(
      "-90",
    );
    await expect(renamed.getByLabel("Name", { exact: true })).toHaveValue(
      "Art & learning",
    );
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.getByRole("button", { name: "Add track", exact: true }).click();
    await form.getByLabel("Name", { exact: true }).fill("ART & LEARNING");
    await form.getByRole("button", { name: "Create track" }).click();
    await expect(form.getByRole("status")).toContainText("already exists");
    await page.getByRole("button", { name: "Cancel new track" }).click();
    await page.screenshot({
      path: "/private/tmp/memotrail-tracks-mobile.png",
      fullPage: true,
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    expect(errors).toEqual([]);
  } finally {
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
