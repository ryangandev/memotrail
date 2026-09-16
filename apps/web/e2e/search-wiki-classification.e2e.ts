import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("Search filters and labels Life Wiki Kinds and types", async ({
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
  const email = `semantic-search-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  if (!created.data.user) throw new Error("Local Search fixture unavailable.");
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
            body: "I noticed how quiet the room felt.",
            inbox_status: "organized",
            item_kind: "writing",
            item_subtype: "reflection",
            owner_id: ownerID,
            title: "Quiet reflection",
          },
          {
            body: "A very good day at the water.",
            inbox_status: "organized",
            item_kind: "event",
            item_subtype: "memory",
            owner_id: ownerID,
            title: "Marina memory",
          },
        ])
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("people").insert({
          name: "Marina mentor",
          notes: "Taught me to sail.",
          owner_id: ownerID,
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("places").insert({
          name: "Marina dock",
          notes: "A calm place.",
          owner_id: ownerID,
        })
      ).error,
    ).toBeNull();

    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    const visibleResult = (title: string) =>
      page.locator("article:visible").filter({
        has: page.locator("a:visible", { hasText: title }),
      });
    await page.goto("/search?type=memory");
    await expect(page.getByLabel("Kind or type")).toHaveValue("memory");
    await expect(visibleResult("Marina memory")).toBeVisible();
    await expect(visibleResult("Marina memory")).toContainText(
      "Event · Memory",
    );
    await expect(visibleResult("Quiet reflection")).toHaveCount(0);

    await page.goto("/search?q=marina&type=entity");
    await expect(visibleResult("Marina mentor")).toBeVisible();
    await expect(visibleResult("Marina dock")).toBeVisible();
    await page.getByLabel("Kind or type").selectOption("person");
    await page.getByRole("button", { name: "Search", exact: true }).click();
    await expect(page).toHaveURL(/type=person/);
    await expect(visibleResult("Marina mentor")).toBeVisible();
    await expect(visibleResult("Marina dock")).toHaveCount(0);

    await page.waitForLoadState("networkidle");
    await page.getByLabel("Kind or type").press("Tab");
    await page.screenshot({
      fullPage: true,
      path: "/private/tmp/memotrail-semantic-search-desktop.png",
    });
    await page.setViewportSize({ height: 844, width: 390 });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.screenshot({
      fullPage: true,
      path: "/private/tmp/memotrail-semantic-search-mobile.png",
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
