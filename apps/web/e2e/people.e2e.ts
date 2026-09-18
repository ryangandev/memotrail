import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("People saves, links, protects, edits, trashes, and restores on desktop and mobile", async ({
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
  const email = `people-${randomUUID()}@memotrail.local`;
  const password = randomUUID();
  const { data: created, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (error || !created.user)
    throw new Error("Could not create isolated local E2E account.");
  const ownerID = created.user.id;
  try {
    const cookies: { name: string; value: string }[] = [];
    const client = createServerClient(env.API_URL, env.ANON_KEY, {
      cookies: {
        getAll: () => cookies,
        setAll: (values) => {
          for (const v of values)
            cookies.push({ name: v.name, value: v.value });
        },
      },
    });
    const link = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    if (!link.data.properties)
      throw new Error("Could not establish the local fixture session.");
    const signedIn = await client.auth.verifyOtp({
      type: "magiclink",
      token_hash: link.data.properties.hashed_token,
    });
    if (signedIn.error)
      throw new Error(`Local fixture session failed: ${signedIn.error.code}`);
    await context.addCookies(
      cookies.map((c) => ({
        ...c,
        domain: "127.0.0.1",
        path: "/",
        httpOnly: false,
        sameSite: "Lax" as const,
      })),
    );
    const { error: entryError } = await client.from("entries").insert({
      owner_id: ownerID,
      title: "A walk with Alex",
      body: "We talked about learning and life.",
    });
    expect(entryError).toBeNull();
    const errors: string[] = [];
    page.on("pageerror", (e) => errors.push(e.message));
    await page.goto("/people");
    await expect(
      page.locator('[data-page-frame="wide"]').filter({ visible: true }),
    ).toHaveCount(1);
    await expect(
      page.getByRole("heading", { name: "People", exact: true }),
    ).toBeVisible();
    await page.getByRole("button", { name: "Add Person", exact: true }).click();
    const dialog = page.getByRole("dialog");
    await dialog.getByLabel("Name", { exact: true }).fill("Alex");
    await dialog.getByLabel("Relationship").fill("Friend");
    await dialog.getByLabel("Notes").fill("A friend from university.");
    await dialog
      .getByLabel("Link an Item")
      .selectOption({ label: "A walk with Alex" });
    await dialog
      .getByRole("button", { name: "Link Item", exact: true })
      .click();
    await dialog
      .getByRole("button", { name: "Add Person", exact: true })
      .click();
    await expect(dialog).not.toBeVisible();
    const card = page.getByRole("button", { name: /Alex Friend/ });
    await expect(card).toContainText("1 connected Items");
    await page.screenshot({
      caret: "initial",
      animations: "disabled",
      path: "/private/tmp/memotrail-people-desktop.png",
      fullPage: true,
    });
    await card.click();
    await expect(
      dialog.getByRole("button", { name: "Move to Trash" }),
    ).toBeDisabled();
    await dialog.getByText("A walk with Alex", { exact: true }).click();
    await expect(
      dialog.getByText("We talked about learning and life."),
    ).toBeVisible();
    await dialog
      .getByRole("button", { name: "Unlink A walk with Alex" })
      .click();
    await dialog.getByRole("button", { name: "Save changes" }).click();
    await expect(dialog).not.toBeVisible();
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await expect(card).toContainText("0 connected Items");
    await page.screenshot({
      caret: "initial",
      animations: "disabled",
      path: "/private/tmp/memotrail-people-mobile.png",
      fullPage: true,
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);
    await card.click();
    await dialog.getByRole("button", { name: "Move to Trash" }).click();
    await page
      .getByRole("dialog", { name: "Move “Alex” to Trash?", exact: true })
      .getByRole("button", { name: "Move to Trash", exact: true })
      .click();
    await expect(dialog).not.toBeVisible();
    await expect(card).not.toBeVisible();
    await page.goto("/trash");
    await expect(page.getByText("Alex", { exact: true })).toBeVisible();
    await page.getByRole("button", { name: "Restore", exact: true }).click();
    await expect(
      page.getByRole("heading", { name: "Nothing in Trash" }),
    ).toBeVisible();
    await page.goto("/people", { waitUntil: "networkidle" });
    await expect(card).toBeVisible();
    expect(errors).toEqual([]);
  } finally {
    const result = await admin.auth.admin.deleteUser(ownerID);
    if (result.error)
      throw new Error("Could not clean up the isolated local E2E account.");
  }
});
