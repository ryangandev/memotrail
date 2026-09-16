import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("Library browses the complete Life Wiki by Kind and keyword", async ({
  context,
  page,
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
  const email = `wiki-library-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  if (!created.data.user) throw new Error("Local Library fixture unavailable.");
  const ownerID = created.data.user.id;

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
      email,
      type: "magiclink",
    });
    if (!link.data.properties) throw new Error("Local sign-in unavailable.");
    expect(
      (
        await client.auth.verifyOtp({
          token_hash: link.data.properties.hashed_token,
          type: "magiclink",
        })
      ).error,
    ).toBeNull();
    await context.addCookies(
      cookies.map((cookie) => ({
        ...cookie,
        domain: "127.0.0.1",
        httpOnly: false,
        path: "/",
        sameSite: "Lax" as const,
      })),
    );

    expect(
      (
        await client.from("entries").insert([
          {
            body: "The quiet helped me notice what mattered.",
            entry_type: "standard",
            inbox_status: "organized",
            item_kind: "writing",
            item_subtype: "reflection",
            owner_id: ownerID,
            title: "Morning reflection",
          },
          {
            body: "A first glimpse of the Pacific.",
            entry_type: "life_stage",
            inbox_status: "organized",
            item_kind: "event",
            item_subtype: "memory",
            owner_id: ownerID,
            title: "Ocean memory",
          },
        ])
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("people").insert({
          name: "Avery",
          notes: "Met at the marina.",
          owner_id: ownerID,
          relationship_label: "Friend",
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("places").insert({
          city: "San Francisco",
          country: "USA",
          name: "Ocean Beach",
          notes: "Morning walks.",
          owner_id: ownerID,
        })
      ).error,
    ).toBeNull();

    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await page.goto("/library");
    await expect(page.getByRole("heading", { name: "Library" })).toBeVisible();
    await expect(page.getByText("Morning reflection")).toBeVisible();
    await expect(page.getByText("Avery")).toBeVisible();
    await expect(page.getByText("Ocean Beach")).toBeVisible();
    await expect(page.getByText("4 items")).toBeVisible();

    await page.getByLabel("Kind").selectOption("entity");
    await page.getByRole("button", { name: "Browse" }).click();
    await expect(page).toHaveURL(/kind=entity/);
    await expect(page.getByText("Avery")).toBeVisible();
    await expect(page.getByText("Ocean Beach")).toBeVisible();
    await expect(page.getByText("Morning reflection")).not.toBeVisible();

    await page.getByLabel("Kind").selectOption("");
    await page.getByLabel("Find in your Life Wiki").fill("marina");
    await page.getByRole("button", { name: "Browse" }).click();
    await expect(page.getByText("Avery")).toBeVisible();
    await expect(page.getByText("Ocean Beach")).not.toBeVisible();
    await page.waitForLoadState("networkidle");
    await page.getByLabel("Find in your Life Wiki").press("Tab");

    await page.screenshot({
      fullPage: true,
      path: "/private/tmp/memotrail-wiki-library-desktop.png",
    });
    await page.setViewportSize({ height: 844, width: 390 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.screenshot({
      fullPage: true,
      path: "/private/tmp/memotrail-wiki-library-mobile.png",
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);
    expect(errors).toEqual([]);
  } finally {
    await admin.auth.admin.deleteUser(ownerID);
  }
});
