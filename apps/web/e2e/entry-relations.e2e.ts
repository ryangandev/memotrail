import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
test("Ordinary Entries link, navigate backlinks, unlink, and restore relationship history", async ({
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
  const email = `entry-relations-${randomUUID()}@memotrail.local`;
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
            inbox_status: "organized",
            item_kind: "writing",
            item_subtype: "note",
            date_precision: "unknown",
          },
          {
            id: target,
            owner_id: owner,
            title: "How teeth move",
            body: "牙套的学习笔记",
            inbox_status: "organized",
            item_kind: "writing",
            item_subtype: "note",
            date_precision: "unknown",
          },
        ])
      ).error,
    ).toBeNull();
    await page.goto(`/history?entry=${source}`);
    const panel = page.getByRole("region", {
      name: "Related Items",
      exact: true,
    });
    await expect(panel).toBeVisible();
    await panel
      .getByRole("button", { name: "Find Items", exact: true })
      .click();
    await panel.getByLabel("Search related Items").fill("牙套");
    await panel.getByRole("button", { name: "Search", exact: true }).click();
    await panel
      .getByRole("button", { name: "Link How teeth move", exact: true })
      .click();
    await expect(
      panel.getByRole("link", { name: "How teeth move", exact: true }),
    ).toBeVisible();
    const history = (await client.rpc("entry_history", { p_entry_id: source }))
      .data;
    expect(history.current).toMatchObject({
      revision: 2,
      title: "Why I keep learning",
      body: "My original words",
      inbox_status: "organized",
      date_precision: "unknown",
    });
    expect(history.current.links).toHaveLength(1);
    expect(history.versions[0].snapshot.links).toHaveLength(0);
    const native = (
      await client.rpc("entry_relations", {
        p_entry_id: target,
        p_mode: "incoming",
      })
    ).data;
    expect(native.items[0].entry_id).toBe(source);
    await panel
      .getByRole("link", { name: "How teeth move", exact: true })
      .click();
    await expect(page).toHaveURL(new RegExp(`/items/${target}$`));
    await expect(
      page.getByRole("heading", { name: "How teeth move", exact: true }),
    ).toBeVisible();
    await panel
      .getByRole("button", { name: "Linked from", exact: true })
      .click();
    await expect(
      panel.getByRole("link", { name: "Why I keep learning", exact: true }),
    ).toBeVisible();
    await expect(panel.getByRole("button", { name: /Unlink/ })).toHaveCount(0);
    await panel
      .getByRole("link", { name: "Why I keep learning", exact: true })
      .click();
    await expect(page).toHaveURL(new RegExp(`/items/${source}$`));
    await panel
      .getByRole("button", { name: "Unlink How teeth move", exact: true })
      .click();
    await page
      .getByRole("dialog", { name: "Unlink “How teeth move”?", exact: true })
      .getByRole("button", { name: "Unlink Item", exact: true })
      .click();
    await expect(panel.getByText("No matching linked Items.")).toBeVisible();
    const unlinked = (await client.rpc("entry_history", { p_entry_id: source }))
      .data;
    expect(unlinked.current.revision).toBe(3);
    expect(unlinked.current.links).toHaveLength(0);
    expect(
      (
        await client.rpc("restore_entry_version", {
          p_entry_id: source,
          p_version: 2,
          p_expected_revision: 3,
        })
      ).error,
    ).toBeNull();
    await page.reload();
    await expect(
      panel.getByRole("link", { name: "How teeth move", exact: true }),
    ).toBeVisible();
    await panel.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-entry-relations-desktop.png",
    });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await panel.scrollIntoViewIfNeeded();
    await panel.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-entry-relations-mobile-dark.png",
    });
    expect(
      (
        await client.from("entry_links").insert({
          source_entry_id: source,
          target_entry_id: target,
          owner_id: owner,
          relationship: "exploration_source",
        })
      ).error?.code,
    ).toBe("42501");
    expect(
      (
        await client
          .from("entries")
          .update({ deleted_at: new Date().toISOString() })
          .eq("id", target)
      ).error,
    ).toBeNull();
    await panel
      .getByRole("button", { name: "Refresh links", exact: true })
      .click();
    await expect(
      panel.getByText("Writing · Note · In Trash", { exact: true }),
    ).toBeVisible();
    // An intervening writing edit cannot be overwritten by a stale relationship request.
    expect(
      (
        await client
          .from("entries")
          .update({ body: "New words from another device" })
          .eq("id", source)
      ).error,
    ).toBeNull();
    await panel
      .getByRole("button", { name: "Unlink How teeth move", exact: true })
      .click();
    await page
      .getByRole("dialog", { name: "Unlink “How teeth move”?", exact: true })
      .getByRole("button", { name: "Unlink Item", exact: true })
      .click();
    await expect(panel.getByRole("alert")).toContainText("This Item changed");
    expect(
      (await client.rpc("entry_relations", { p_entry_id: source })).data
        .total_count,
    ).toBe(1);
    await panel
      .getByRole("button", { name: "Refresh links", exact: true })
      .click();
    await expect(panel.getByRole("alert")).toHaveCount(0);
    const a = randomUUID(),
      b = randomUUID();
    expect(
      (
        await client.from("entries").insert([
          { id: a, owner_id: owner, title: "Parallel A" },
          { id: b, owner_id: owner, title: "Parallel B" },
        ])
      ).error,
    ).toBeNull();
    const competing = await Promise.all(
      [a, b].map((id) =>
        client.rpc("set_entry_relation", {
          p_entry_id: source,
          p_target_id: id,
          p_expected_revision: 5,
          p_linked: true,
        }),
      ),
    );
    expect(competing.every((response) => response.error === null)).toBe(true);
    expect(competing.map((response) => response.data).sort()).toEqual([
      6,
      null,
    ]);
    const current = (await client.rpc("entry_history", { p_entry_id: source }))
      .data.current;
    expect(current).toMatchObject({
      revision: 6,
      body: "New words from another device",
      inbox_status: "organized",
    });
    expect(current.links).toHaveLength(2);
  } finally {
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
