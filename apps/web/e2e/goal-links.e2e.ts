import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("Want to Do edits keep older related links without showing them", async ({
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
    const saved = await client.rpc("save_goal_entry", {
      p_title: "Patient learning",
      p_body: "Original intention",
      p_status: "active",
      p_target_date: null,
      p_tag_names: [],
      p_entry_id: null,
      p_expected_revision: null,
    });
    expect(saved.error).toBeNull();
    const id = saved.data[0].entry_id;
    // Older Goals could carry general links. Want to Do no longer edits them.
    expect(
      (
        await admin.from("entry_links").insert(
          [hiddenID, activeID].map((target) => ({
            owner_id: owner,
            relationship: "related",
            source_entry_id: id,
            target_entry_id: target,
          })),
        )
      ).error,
    ).toBeNull();
    expect(
      (
        await client
          .from("entries")
          .update({ deleted_at: new Date().toISOString() })
          .eq("id", hiddenID)
      ).error,
    ).toBeNull();
    await page.goto("/goals/" + id);
    const main = page.getByRole("main");
    await expect(main).not.toContainText("progress note");
    await page.getByRole("button", { name: "Edit Want to Do" }).click();
    await expect(main).not.toContainText("progress note");
    await expect(main.getByText(/Related/)).toHaveCount(0);
    await main.getByRole("textbox", { name: "Title" }).fill("Patient practice");
    await main
      .getByRole("button", { name: "Save changes", exact: true })
      .click();
    await expect(
      page.getByRole("button", { name: "Edit Want to Do" }),
    ).toBeVisible();
    await expect(
      page.getByRole("heading", { name: "Patient practice" }),
    ).toBeVisible();
    await expect
      .poll(
        async () =>
          (
            await client
              .from("entry_links")
              .select("target_entry_id")
              .eq("source_entry_id", id)
              .eq("relationship", "related")
          ).data?.length,
      )
      .toBe(2);
    expect(uiErrors).toEqual([]);
  } finally {
    await admin.auth.admin.deleteUser(owner);
  }
});
