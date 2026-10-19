import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

// Content widths at 1800 by 900, where the workspace beside the 240 px sidebar is 1560 px wide.
// Reading and list frames start 64 px into it, and full keeps a 40 px edge on both sides.
// A detail page, with a back link, has a larger title.
const pageFamilies = [
  { path: "/library", width: "list", content: 960 },
  { path: "/settings", width: "reading", content: 720 },
  { path: "/settings/export", width: "reading", content: 720, detail: true },
  { path: "/settings/import", width: "reading", content: 720 },
  { path: "/search", width: "list", content: 960 },
  { path: "/tags", width: "list", content: 960 },
  { path: "/trash", width: "list", content: 960 },
  { path: "/reviews", width: "list", content: 960 },
  { path: "/", width: "list", content: 960 },
  { path: "/first-times", width: "list", content: 960 },
  { path: "/timeline", width: "full", content: 1480 },
] as const;

const focusedViewPaths = new Set(["/first-times"]);

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
      // The route loading fallback is a PageFrame too; measure the page, not the fallback.
      await expect(
        page.getByRole("status", { name: "Loading page" }),
      ).toHaveCount(0);
      const frame = page
        .locator(`[data-page-frame="${family.width}"]`)
        .filter({ visible: true });
      await expect(frame).toHaveCount(1);
      await expect(frame).toBeVisible();
      const title = frame.locator("[data-ui-page-header] h1");
      await expect(title).toHaveCount(1);
      await expect(title).toHaveCSS(
        "font-size",
        "detail" in family ? "34px" : "32px",
      );
      await expect(title).toHaveCSS("margin-top", "0px");
      // Every page starts at the same left edge, so its title never moves sideways.
      // A route transition can measure the frame before layout settles.
      await expect
        .poll(() =>
          frame.evaluate((element) => {
            const content = element.querySelector("[data-ui-page-header]")!;
            const box = content.getBoundingClientRect();
            return [Math.round(box.left), Math.round(box.width)];
          }),
        )
        .toEqual([
          family.width === "full" ? 240 + 40 : 240 + 64,
          family.content,
        ]);
      if (focusedViewPaths.has(family.path)) {
        await expectFocusedViewContentGap(frame, 32);
      }
      // Leave only after the page finishes loading its data.
      await page.waitForLoadState("networkidle");
    }

    await page.setViewportSize({ width: 390, height: 844 });
    for (const family of pageFamilies) {
      await page.goto(family.path);
      await expect(
        page.getByRole("status", { name: "Loading page" }),
      ).toHaveCount(0);
      const frame = page
        .locator(`[data-page-frame="${family.width}"]`)
        .filter({ visible: true });
      await expect(frame).toHaveCount(1);
      await expect(frame).toBeVisible();
      const title = frame.locator("[data-ui-page-header] h1");
      await expect(title).toHaveCSS("font-size", "26px");
      await expect(title).toHaveCSS("margin-top", "0px");
      // On a phone every width runs the full screen inside the 16 px gutters.
      expect(
        await frame.evaluate((element) => {
          const content = element.querySelector("[data-ui-page-header]")!;
          const box = content.getBoundingClientRect();
          return [Math.round(box.left), Math.round(box.width)];
        }),
      ).toEqual([16, 358]);
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
