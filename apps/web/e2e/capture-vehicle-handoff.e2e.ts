import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

test("Inbox Capture creates a linked Vehicle through the specialized form", async ({
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
  const email = `capture-vehicle-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  if (!created.data.user) throw new Error("Local Vehicle fixture unavailable.");
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
          title: "My first EV",
          body: "Quiet drives around the bay.",
          item_kind: "capture",
          item_subtype: "quick_capture",
          inbox_status: "unreviewed",
          date_precision: "unknown",
        })
      ).error,
    ).toBeNull();

    await page.goto("/inbox");
    const card = page.locator("article").filter({
      has: page.getByRole("heading", { name: "My first EV" }),
    });
    await card.getByRole("button", { name: "Organize", exact: true }).click();
    await page
      .getByRole("dialog", { name: "Organize Capture" })
      .getByRole("link", { name: "Vehicle", exact: true })
      .click();

    await expect(page).toHaveURL(
      new RegExp(`/vehicles\\?source=${captureID}$`),
    );
    const editor = page.getByRole("dialog", {
      name: "Create a Vehicle from this Capture",
    });
    await expect(
      editor.getByText("Starting from an Inbox Capture"),
    ).toBeVisible();
    await expect(
      editor.getByLabel("Name or nickname", { exact: true }),
    ).toHaveValue("My first EV");
    await expect(editor.getByRole("textbox", { name: /Memories/ })).toHaveValue(
      "Quiet drives around the bay.",
    );
    await editor.getByRole("textbox", { name: /Make/ }).fill("Toyota");
    await editor.getByRole("textbox", { name: /Model/ }).fill("RAV4");
    await editor.getByRole("spinbutton", { name: /Model year/ }).fill("2025");
    await editor.getByRole("textbox", { name: /Color/ }).fill("White Pearl");
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-capture-vehicle-handoff.png",
      fullPage: true,
    });
    await editor
      .getByRole("button", { name: "Add Vehicle", exact: true })
      .click();
    await expect(editor).not.toBeVisible();
    await expect(page).toHaveURL(/\/vehicles$/);
    await expect(
      page.getByRole("button", { name: /My first EV/ }),
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
    const vehicle = await client
      .from("entries")
      .select(
        "id,item_kind,item_subtype,title,vehicles(make,model,model_year,color)",
      )
      .eq("owner_id", ownerID)
      .eq("item_kind", "entity")
      .eq("item_subtype", "vehicle")
      .single();
    expect(vehicle.data).toMatchObject({
      item_kind: "entity",
      item_subtype: "vehicle",
      title: "My first EV",
      vehicles: [
        {
          make: "Toyota",
          model: "RAV4",
          model_year: 2025,
          color: "White Pearl",
        },
      ],
    });
    expect(uiErrors).toEqual([]);
  } finally {
    await admin.auth.admin.deleteUser(ownerID);
  }
});
