import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("Habit check-in editing retains an existing Entry link and supports explicit linking", async ({
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
  const email = `habit-link-${randomUUID()}@memotrail.local`;
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
        sameSite: "Lax" as const,
      })),
    );
    const habit = randomUUID(),
      entry = randomUUID();
    expect(
      (
        await client.from("entries").insert({
          id: entry,
          owner_id: owner,
          title: "学习笔记",
          body: "Original reflection stays unchanged.",
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("habits").insert({
          id: habit,
          owner_id: owner,
          name: "Read daily",
          starts_on: "2024-01-01",
          schedule: { kind: "daily" },
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("habit_occurrences").insert({
          habit_id: habit,
          owner_id: owner,
          local_date: "2024-03-03",
          status: "completed",
          entry_id: entry,
        })
      ).error,
    ).toBeNull();
    await page.goto(`/habits?habit=${habit}&year=2024&date=2024-03-03`);
    await page
      .getByRole("button", { name: "Edit check-in", exact: true })
      .click();
    const dialog = page.getByRole("dialog");
    await dialog
      .getByRole("textbox", { name: /Note/ })
      .fill("A revised check-in note.");
    await dialog
      .getByRole("button", { name: "Update check-in", exact: true })
      .click();
    await expect(dialog).not.toBeVisible();
    const saved = await client
      .from("habit_occurrences")
      .select("entry_id,note,revision")
      .eq("habit_id", habit)
      .eq("local_date", "2024-03-03")
      .single();
    expect(saved.error).toBeNull();
    expect(saved.data?.entry_id).toBe(entry);
    const open = async () => {
      await page
        .getByRole("button", { name: "Edit check-in", exact: true })
        .click();
      await expect(
        dialog.getByRole("heading", { name: "Linked Entry", exact: true }),
      ).toBeVisible();
    };
    const checkLink = async (expected: string | null) => {
      const result = await client
        .from("habit_occurrences")
        .select("entry_id,revision")
        .eq("habit_id", habit)
        .eq("local_date", "2024-03-03")
        .single();
      expect(result.error).toBeNull();
      expect(result.data?.entry_id).toBe(expected);
      return result.data!.revision;
    };
    await open();
    await expect(
      dialog.getByRole("link", { name: "学习笔记", exact: true }),
    ).toBeVisible();
    const popupPromise = context.waitForEvent("page");
    await dialog.getByRole("link", { name: "学习笔记", exact: true }).click();
    const original = await popupPromise;
    await expect(
      original.getByText("Original reflection stays unchanged.", {
        exact: true,
      }),
    ).toBeVisible();
    await original.close();
    await dialog
      .getByRole("button", { name: "Remove link", exact: true })
      .click();
    await dialog
      .getByRole("button", { name: "Close check-in editor", exact: true })
      .click();
    await checkLink(entry);
    expect(
      (
        await client
          .from("entries")
          .update({ deleted_at: new Date().toISOString() })
          .eq("id", entry)
      ).error,
    ).toBeNull();
    await open();
    await expect(
      dialog.getByText("In Trash. This link is kept unless you remove it.", {
        exact: true,
      }),
    ).toBeVisible();
    await dialog
      .getByRole("textbox", { name: /Note/ })
      .fill("Keep the recoverable context.");
    await dialog
      .getByRole("button", { name: "Update check-in", exact: true })
      .click();
    await expect(dialog).not.toBeVisible();
    await checkLink(entry);
    await open();
    await dialog
      .getByRole("button", { name: "Remove link", exact: true })
      .click();
    await dialog
      .getByRole("button", { name: "Update check-in", exact: true })
      .click();
    await expect(dialog).not.toBeVisible();
    await checkLink(null);
    expect(
      (
        await client
          .from("entries")
          .update({ deleted_at: null })
          .eq("id", entry)
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("entries").insert(
          Array.from({ length: 23 }, (_, index) => ({
            owner_id: owner,
            title: `Paging ${String(index).padStart(2, "0")}`,
            body: "Synthetic context",
          })),
        )
      ).error,
    ).toBeNull();
    await open();
    await dialog
      .getByRole("button", { name: "Next Entries", exact: true })
      .click();
    await expect(dialog.getByText("Page 2", { exact: true })).toBeVisible();
    await dialog
      .getByRole("textbox", { name: "Find an Entry", exact: true })
      .fill("学习");
    await dialog
      .getByRole("button", { name: "Search Entries", exact: true })
      .click();
    await expect(
      dialog.getByRole("button", { name: "Link 学习笔记", exact: true }),
    ).toBeVisible();
    await dialog
      .getByRole("button", { name: "Link 学习笔记", exact: true })
      .click();
    await checkLink(null);
    await page.setViewportSize({ width: 1440, height: 1000 });
    await dialog
      .getByRole("heading", { name: "Linked Entry", exact: true })
      .scrollIntoViewIfNeeded();
    await page.screenshot({
      path: "/private/tmp/memotrail-habit-link-desktop.png",
    });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await dialog
      .getByRole("heading", { name: "Linked Entry", exact: true })
      .scrollIntoViewIfNeeded();
    await page.screenshot({
      path: "/private/tmp/memotrail-habit-link-mobile.png",
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);
    await dialog
      .getByRole("button", { name: "Update check-in", exact: true })
      .click();
    await expect(dialog).not.toBeVisible();
    const revision = await checkLink(entry);
    const competed = await Promise.all(
      ["One", "Two"].map((note) =>
        client.rpc("save_habit_check_in", {
          p_habit_id: habit,
          p_local_date: "2024-03-03",
          p_status: "completed",
          p_measured_value: null,
          p_note: note,
          p_entry_id: entry,
          p_expected_revision: revision,
        }),
      ),
    );
    expect(competed.every((result) => result.error === null)).toBe(true);
    expect(competed.map((result) => result.data.length).sort()).toEqual([0, 1]);
    expect(
      (
        await client.rpc("record_habit_occurrence", {
          p_habit_id: habit,
          p_local_date: "2024-03-03",
          p_status: "completed",
          p_measured_value: null,
          p_note: "Older client",
          p_entry_id: null,
          p_expected_revision: revision + 1,
        })
      ).error,
    ).toBeNull();
    await checkLink(entry);
    expect(
      (await client.from("entries").select("body").eq("id", entry).single())
        .data?.body,
    ).toBe("Original reflection stays unchanged.");
  } finally {
    await page.close();
    expect(owner).toMatch(/^[0-9a-f-]{36}$/);
    execFileSync(
      "docker",
      [
        "exec",
        "supabase_db_memotrail",
        "psql",
        "-U",
        "postgres",
        "-d",
        "postgres",
        "-v",
        "ON_ERROR_STOP=1",
        "-c",
        `BEGIN; DELETE FROM public.habit_occurrences WHERE owner_id='${owner}'; DELETE FROM public.habits WHERE owner_id='${owner}'; COMMIT;`,
      ],
      { stdio: "pipe" },
    );
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
