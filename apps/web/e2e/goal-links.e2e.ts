import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("Goal edits retain links to Entries in Trash until they are restored", async ({
  page,
  context,
}) => {
  const uiErrors: string[] = [];
  page.on("pageerror", (error) => uiErrors.push(error.message));
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
  const email = `goal-link-lifecycle-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  const owner = created.data.user!.id;
  try {
    const cookies: { name: string; value: string }[] = [];
    const client = createServerClient(env.API_URL, env.ANON_KEY, {
      cookies: {
        getAll: () => cookies,
        setAll: (values) => {
          cookies.push(
            ...values.map((v) => ({ name: v.name, value: v.value })),
          );
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
      cookies.map((c) => ({
        ...c,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax",
        httpOnly: false,
      })),
    );

    const hiddenID = randomUUID(),
      activeID = randomUUID();
    expect(
      (
        await client.from("entries").insert([
          {
            id: hiddenID,
            owner_id: owner,
            title: "Hidden progress note",
            body: "Original progress",
          },
          {
            id: activeID,
            owner_id: owner,
            title: "Visible progress note",
            body: "Current progress",
          },
        ])
      ).error,
    ).toBeNull();
    const args = {
      p_title: "Patient learning",
      p_body: "Original intention",
      p_horizon: "long_term",
      p_status: "active",
      p_target_date: null,
      p_collection_names: [],
      p_tag_names: [],
      p_related_entry_ids: [hiddenID, activeID],
      p_entry_id: null,
      p_expected_revision: null,
    };
    const saved = await client.rpc("save_goal_entry", args);
    expect(saved.error).toBeNull();
    const id = saved.data[0].entry_id;
    expect(
      (
        await client
          .from("entries")
          .update({ deleted_at: new Date().toISOString() })
          .eq("id", hiddenID)
      ).error,
    ).toBeNull();
    await page.goto("/goals?entry=" + id);
    const dialog = page.getByRole("dialog");
    await expect(dialog).not.toContainText("Hidden progress note");
    await expect(dialog).toContainText("Visible progress note");
    await dialog
      .getByRole("button", { name: "Save changes", exact: true })
      .click();
    await expect(dialog).not.toBeVisible();
    expect(
      (
        await client
          .from("entry_links")
          .select("target_entry_id")
          .eq("source_entry_id", id)
          .eq("target_entry_id", hiddenID)
      ).data,
    ).toHaveLength(1);
    const revision = (
      await client.from("entries").select("revision").eq("id", id).single()
    ).data!.revision;
    expect(
      (
        await client.rpc("save_goal_entry", {
          ...args,
          p_entry_id: id,
          p_expected_revision: revision,
          p_related_entry_ids: [],
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client
          .from("entry_links")
          .select("target_entry_id")
          .eq("source_entry_id", id)
          .eq("relationship", "related")
      ).data,
    ).toEqual([{ target_entry_id: hiddenID }]);
    await page.goto("/trash");
    await page.getByRole("button", { name: "Restore", exact: true }).click();
    await expect(
      page.getByText("Hidden progress note", { exact: true }),
    ).not.toBeVisible();
    await page.goto("/goals?entry=" + id);
    await expect(
      dialog.getByRole("button", {
        name: "Remove related Item Hidden progress note",
        exact: true,
      }),
    ).toBeVisible();
    await expect(
      dialog.getByRole("button", {
        name: "Remove related Item Visible progress note",
        exact: true,
      }),
    ).not.toBeVisible();
    await dialog
      .getByRole("button", {
        name: "Remove related Item Hidden progress note",
        exact: true,
      })
      .click();
    await dialog
      .getByRole("button", { name: "Save changes", exact: true })
      .click();
    await expect(dialog).not.toBeVisible();
    expect(
      (
        await client
          .from("entry_links")
          .select("target_entry_id")
          .eq("source_entry_id", id)
          .eq("relationship", "related")
      ).data,
    ).toHaveLength(0);
    expect(uiErrors).toEqual([]);
  } finally {
    await admin.auth.admin.deleteUser(owner);
  }
});
