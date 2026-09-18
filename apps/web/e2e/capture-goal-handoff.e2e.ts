import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

test("Inbox Capture creates a linked Goal through the specialized form", async ({
  context,
  page,
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
  const email = `capture-goal-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  if (!created.data.user) throw new Error("Local Goal fixture unavailable.");
  const ownerID = created.data.user.id;
  const captureID = randomUUID();

  try {
    const cookies: { name: string; value: string }[] = [];
    const client = createServerClient(env.API_URL, env.ANON_KEY, {
      cookies: {
        getAll: () => cookies,
        setAll: (values) => {
          cookies.push(
            ...values.map((value) => ({
              name: value.name,
              value: value.value,
            })),
          );
        },
      },
    });
    const link = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    if (!link.data.properties) throw new Error("Local sign-in unavailable.");
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
        sameSite: "Lax" as const,
        httpOnly: false,
      })),
    );
    expect(
      (
        await client.from("entries").insert({
          id: captureID,
          owner_id: ownerID,
          title: "Learn to sail",
          body: "A wish I want to make concrete.",
          item_kind: "capture",
          item_subtype: "quick_capture",
          inbox_status: "unreviewed",
          date_precision: "unknown",
        })
      ).error,
    ).toBeNull();

    await page.goto("/inbox");
    const card = page.locator("article").filter({
      has: page.getByRole("heading", { name: "Learn to sail" }),
    });
    await card.getByRole("button", { name: "Organize", exact: true }).click();
    await page
      .getByRole("dialog", { name: "Organize Capture" })
      .getByRole("link", { name: "Goal", exact: true })
      .click();

    await expect(page).toHaveURL(new RegExp(`/goals\\?source=${captureID}$`));
    const editor = page.getByRole("dialog", {
      name: "Create a Goal from this Capture",
    });
    await expect(
      editor.getByText("Starting from an Inbox Capture"),
    ).toBeVisible();
    await expect(editor.getByLabel("Title", { exact: true })).toHaveValue(
      "Learn to sail",
    );
    await expect(
      editor.getByRole("textbox", { name: /Reflection/ }),
    ).toHaveValue("A wish I want to make concrete.");
    await editor
      .getByRole("combobox", { name: "Horizon" })
      .selectOption("long_term");
    await editor
      .getByRole("combobox", { name: "Reflective state" })
      .selectOption("active");
    await editor.getByLabel(/Target date/).fill("2028-06-01");
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-capture-goal-handoff.png",
      fullPage: true,
    });
    await editor.getByRole("button", { name: "Add Goal", exact: true }).click();
    await expect(editor).not.toBeVisible();
    await expect(page).toHaveURL(/\/goals$/);
    await expect(
      page.getByRole("button", { name: /Learn to sail/ }),
    ).toBeVisible();

    const source = await client
      .from("entries")
      .select("item_kind,item_subtype,inbox_status")
      .eq("id", captureID)
      .single();
    expect(source.data).toEqual({
      item_kind: "capture",
      item_subtype: "source_capture",
      inbox_status: "organized",
    });
    const goal = await client
      .from("entries")
      .select(
        "id,item_kind,item_subtype,title,goals(horizon,status,target_date)",
      )
      .eq("owner_id", ownerID)
      .eq("item_kind", "goal")
      .single();
    expect(goal.data).toMatchObject({
      item_kind: "goal",
      item_subtype: "goal",
      title: "Learn to sail",
      goals: [
        {
          horizon: "long_term",
          status: "active",
          target_date: "2028-06-01",
        },
      ],
    });
    const provenance = await client
      .from("entry_links")
      .select("source_entry_id,target_entry_id,relationship")
      .eq("owner_id", ownerID)
      .in("relationship", ["derived", "derived_from"]);
    expect(provenance.data).toHaveLength(2);
    expect(uiErrors).toEqual([]);
  } finally {
    await admin.auth.admin.deleteUser(ownerID);
  }
});
