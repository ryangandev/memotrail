import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

const pageFamilies = [
  { path: "/library", variant: "standard", width: 960 },
  { path: "/settings", variant: "compact", width: 880 },
  { path: "/settings/ai", variant: "compact", width: 880 },
  { path: "/settings/export", variant: "compact", width: 880 },
  { path: "/search", variant: "standard", width: 960 },
  { path: "/tags", variant: "standard", width: 960 },
  { path: "/trash", variant: "standard", width: 960 },
  { path: "/", variant: "wide", width: 1080 },
  { path: "/first-times", variant: "wide", width: 1080 },
  { path: "/goals", variant: "wide", width: 1080 },
  { path: "/homes", variant: "wide", width: 1080 },
  { path: "/vehicles", variant: "wide", width: 1080 },
  { path: "/timeline", variant: "canvas", width: 1180 },
] as const;

const focusedViewPaths = new Set([
  "/first-times",
  "/goals",
  "/homes",
  "/vehicles",
]);

test("authenticated pages use the shared responsive page frame", async ({
  context,
  page,
}) => {
  const env = JSON.parse(
    execFileSync("supabase", ["status", "-o", "json"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }),
  );
  const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
  const email = `page-frame-${randomUUID()}@memotrail.local`;
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
      cookies.map((cookie) => ({
        ...cookie,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax" as const,
      })),
    );

    await page.setViewportSize({ width: 1800, height: 900 });
    for (const family of pageFamilies) {
      await page.goto(family.path);
      const frame = page
        .locator(`[data-page-frame="${family.variant}"]`)
        .filter({ visible: true });
      await expect(frame).toHaveCount(1);
      await expect(frame).toBeVisible();
      for (const title of await frame
        .locator("[data-ui-page-header] h1")
        .all()) {
        const canonicalSize = await title.evaluate((element) =>
          getComputedStyle(element)
            .getPropertyValue("--mt-font-size-display")
            .trim(),
        );
        await expect(title).toHaveCSS("font-size", canonicalSize);
        await expect(title).toHaveCSS("margin-top", "0px");
      }
      expect(
        await frame.evaluate(
          (element) => element.getBoundingClientRect().width,
        ),
      ).toBeCloseTo(family.width, 0);
      if (focusedViewPaths.has(family.path)) {
        await expectFocusedViewContentGap(frame, 32);
      }
      // Leave only after the page finishes loading its data.
      await page.waitForLoadState("networkidle");
    }

    await page.setViewportSize({ width: 390, height: 844 });
    for (const family of pageFamilies) {
      await page.goto(family.path);
      const frame = page
        .locator(`[data-page-frame="${family.variant}"]`)
        .filter({ visible: true });
      await expect(frame).toHaveCount(1);
      await expect(frame).toBeVisible();
      for (const title of await frame
        .locator("[data-ui-page-header] h1")
        .all()) {
        const canonicalSize = await title.evaluate((element) =>
          getComputedStyle(element)
            .getPropertyValue("--mt-font-size-title")
            .trim(),
        );
        await expect(title).toHaveCSS("font-size", canonicalSize);
        await expect(title).toHaveCSS("margin-top", "0px");
      }
      expect(
        await frame.evaluate(
          (element) => element.getBoundingClientRect().width,
        ),
      ).toBeCloseTo(366, 0);
      if (focusedViewPaths.has(family.path)) {
        await expectFocusedViewContentGap(frame, 24);
      }
      // Leave only after the page finishes loading its data.
      await page.waitForLoadState("networkidle");
    }
  } finally {
    await page.close();
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});

async function expectFocusedViewContentGap(
  frame: import("@playwright/test").Locator,
  expectedGap: number,
) {
  const summary = frame.locator("[data-focused-view-summary]");
  const content = frame.locator("[data-focused-view-content]");
  await expect(summary).toBeVisible();
  await expect(content).toBeVisible();
  const gap = await summary.evaluate((element) => {
    const summaryRect = element.getBoundingClientRect();
    const contentRect = element.nextElementSibling!.getBoundingClientRect();
    return contentRect.top - summaryRect.bottom;
  });
  expect(gap).toBeCloseTo(expectedGap, 0);
}
