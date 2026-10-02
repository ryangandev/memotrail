import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";

test("Exploration RPCs serialize competing devices and preserve original writing", async () => {
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
  const email = `explore-contract-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  if (!created.data.user)
    throw new Error("Synthetic exploration user unavailable.");
  const owner = created.data.user.id;
  try {
    const link = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    if (!link.data.properties)
      throw new Error("Synthetic sign-in unavailable.");
    const client = createClient(env.API_URL, env.ANON_KEY, {
      auth: { persistSession: false },
    });
    const signed = await client.auth.verifyOtp({
      type: "magiclink",
      token_hash: link.data.properties.hashed_token,
    });
    expect(signed.error).toBeNull();
    const secondDevice = createClient(env.API_URL, env.ANON_KEY, {
      auth: { persistSession: false },
      global: {
        headers: {
          Authorization: `Bearer ${signed.data.session!.access_token}`,
        },
      },
    });
    const entryID = randomUUID();
    const original = "我想探索一下，为什么不断学习很重要？";
    expect(
      (
        await client.from("entries").insert({
          id: entryID,
          owner_id: owner,
          title: "Original",
          body: original,
          date_precision: "unknown",
        })
      ).error,
    ).toBeNull();
    const preferences = (await client.rpc("ai_workspace")).data.preferences;
    expect(
      (
        await client.rpc("save_ai_preferences", {
          p_preferences: { ...preferences, enabled: true, explore: true },
          p_expected_revision: preferences.revision,
        })
      ).error,
    ).toBeNull();
    const turnID = randomUUID();
    const claim = (id: string) =>
      admin.rpc("claim_exploration_turn", {
        p_owner_id: owner,
        p_entry_id: entryID,
        p_request_id: id,
        p_question: "Explore this question.",
        p_source_revision: 1,
      });
    const duplicates = await Promise.all(
      Array.from({ length: 8 }, () => claim(turnID)),
    );
    expect(duplicates.every((r) => !r.error)).toBe(true);
    expect(duplicates.filter((r) => r.data.claimed)).toHaveLength(1);
    const competitors = await Promise.all(
      Array.from({ length: 4 }, () => claim(randomUUID())),
    );
    expect(
      competitors.every((r) => r.error?.message === "exploration_busy"),
    ).toBe(true);
    expect(
      (
        await admin.rpc("finish_exploration_turn", {
          p_owner_id: owner,
          p_request_id: turnID,
          p_answer: "A synthetic answer for contract validation only.",
          p_model: "claude-haiku-4-5-20251001",
          p_error_code: null,
        })
      ).data,
    ).toBe(true);
    const saveID = randomUUID();
    const save = (id: string, index: number) =>
      (index % 2 ? client : secondDevice).rpc("save_exploration_conclusion", {
        p_request_id: id,
        p_turn_id: turnID,
        p_title: "My edited conclusion",
        p_body: "A conclusion I chose to save.",
      });
    const saved = await Promise.all(
      Array.from({ length: 8 }, (_, i) => save(saveID, i)),
    );
    expect(
      saved.every((r) => !r.error),
      JSON.stringify(saved.map((r) => r.error)),
    ).toBe(true);
    expect(saved.filter((r) => r.data.created)).toHaveLength(1);
    expect(new Set(saved.map((r) => r.data.entry_id)).size).toBe(1);
    const savedID = saved[0].data.entry_id;
    const more = await Promise.all(
      Array.from({ length: 4 }, (_, i) => save(randomUUID(), i)),
    );
    expect(more.every((r) => !r.error && r.data.created)).toBe(true);
    const source = await client
      .from("entries")
      .select("body,revision,inbox_status")
      .eq("id", entryID)
      .single();
    expect(source.data).toEqual({
      body: original,
      revision: 6,
      inbox_status: "unreviewed",
    });
    const links = await client
      .from("entry_links")
      .select("source_entry_id,target_entry_id,relationship")
      .eq("owner_id", owner);
    expect(links.data).toHaveLength(10);
    expect(
      links.data?.filter((row) => row.source_entry_id === savedID),
    ).toEqual([
      {
        source_entry_id: savedID,
        target_entry_id: entryID,
        relationship: "exploration_source",
      },
    ]);
    const workspace = (
      await secondDevice.rpc("exploration_workspace", { p_entry_id: entryID })
    ).data;
    expect(workspace.turns).toHaveLength(1);
    expect(workspace.turns[0].saved_entries).toHaveLength(5);
    const histories = (
      await client.rpc("entry_history", { p_entry_id: entryID })
    ).data;
    expect(histories.total_count).toBe(5);
    expect(
      histories.versions.every(
        (v: { snapshot: { body: string } }) => v.snapshot.body === original,
      ),
    ).toBe(true);
    expect((await client.rpc("ai_workspace")).data.recent_usage).toHaveLength(
      0,
    );
  } finally {
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
