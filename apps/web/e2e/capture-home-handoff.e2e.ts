import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

test("Inbox Capture creates a linked Home through the specialized form", async ({
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
  const email = `capture-home-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  if (!created.data.user) throw new Error("Local Home fixture unavailable.");
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
          title: "Moved near the lake",
          body: "First evening in the new apartment.",
          item_kind: "capture",
          item_subtype: "quick_capture",
          inbox_status: "unreviewed",
          date_precision: "unknown",
        })
      ).error,
    ).toBeNull();

    await page.goto("/inbox");
    const card = page.locator("article").filter({
      has: page.getByRole("heading", { name: "Moved near the lake" }),
    });
    await card.getByRole("button", { name: "Organize", exact: true }).click();
    const review = page.getByRole("dialog", { name: "Organize Capture" });
    await expect(
      review.getByText("Organize as", { exact: true }),
    ).toBeVisible();
    await expect(
      review.getByRole("combobox", { name: "Kind", exact: true }),
    ).toHaveValue("writing");
    await expect(
      review.getByRole("button", { name: "Save to Library", exact: true }),
    ).toBeVisible();
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-capture-organizer.png",
      fullPage: true,
    });
    await review.getByRole("link", { name: "Home", exact: true }).click();

    await expect(page).toHaveURL(new RegExp(`/homes\\?source=${captureID}$`));
    const editor = page.getByRole("dialog", {
      name: "Create a Home from this Capture",
    });
    await expect(
      editor.getByText("Starting from an Inbox Capture"),
    ).toBeVisible();
    await expect(editor.getByLabel("Home name", { exact: true })).toHaveValue(
      "Moved near the lake",
    );
    await expect(editor.getByRole("textbox", { name: /Memories/ })).toHaveValue(
      "First evening in the new apartment.",
    );
    await editor
      .getByLabel("Place name", { exact: true })
      .fill("Lake Merritt apartment");
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-capture-home-handoff.png",
      fullPage: true,
    });
    await editor.getByRole("button", { name: "Add Home", exact: true }).click();
    await expect(editor).not.toBeVisible();
    await expect(page).toHaveURL(/\/homes$/);
    await expect(
      page.getByRole("button", { name: /Moved near the lake/ }),
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
    const home = await client
      .from("entries")
      .select("id,item_kind,item_subtype,title")
      .eq("owner_id", ownerID)
      .eq("item_kind", "entity")
      .eq("item_subtype", "home")
      .single();
    expect(home.data).toMatchObject({
      item_kind: "entity",
      item_subtype: "home",
      title: "Moved near the lake",
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
