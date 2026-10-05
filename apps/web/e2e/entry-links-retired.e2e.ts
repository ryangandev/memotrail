import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
test("Item pages offer no general links between Entries", async ({
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
  const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY);
  const email = `entry-links-retired-${randomUUID()}@memotrail.local`;
  const user = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  expect(user.error).toBeNull();
  const owner = user.data.user!.id,
    source = randomUUID(),
    target = randomUUID();
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
    expect(
      (
        await client.auth.verifyOtp({
          type: "magiclink",
          token_hash: link.data.properties!.hashed_token,
        })
      ).error,
    ).toBeNull();
    await context.addCookies(
      cookies.map((c) => ({
        ...c,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax",
      })),
    );
    expect(
      (
        await client.from("entries").insert([
          {
            id: source,
            owner_id: owner,
            title: "Why I keep learning",
            body: "My original words",
            item_kind: "entry",
            item_subtype: "entry",
            date_precision: "unknown",
          },
          {
            id: target,
            owner_id: owner,
            title: "How teeth move",
            body: "牙套的学习笔记",
            item_kind: "entry",
            item_subtype: "entry",
            date_precision: "unknown",
          },
        ])
      ).error,
    ).toBeNull();
    expect(
      (
        await client.rpc("set_entry_relation", {
          p_entry_id: source,
          p_target_id: target,
          p_expected_revision: 1,
          p_linked: true,
        })
      ).error?.code,
    ).toBe("PGRST202");
    for (const id of [source, target]) {
      await page.goto(`/items/${id}`);
      await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
      await expect(
        page.getByRole("region", { name: "Current photos", exact: true }),
      ).toBeVisible();
      await expect(
        page.getByRole("region", { name: "Related Items", exact: true }),
      ).toHaveCount(0);
      await expect(
        page.getByRole("button", { name: "Find Items", exact: true }),
      ).toHaveCount(0);
      await expect(
        page.getByRole("button", { name: "Linked from", exact: true }),
      ).toHaveCount(0);
    }
    const current = (await client.rpc("entry_detail", { p_entry_id: source }))
      .data;
    expect(current).toMatchObject({
      revision: 1,
      body: "My original words",
      links: [],
    });
    expect(current).not.toHaveProperty("related_entry_ids");
  } finally {
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
