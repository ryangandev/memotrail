import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

test("Vehicle cards share one grid row and keep their visual flush to the border", async ({
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
  const email = `vehicle-layout-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
    password: randomUUID(),
  });
  if (!created.data.user) throw new Error("Could not create local test account.");
  const owner = created.data.user.id;

  try {
    const cookies: { name: string; value: string }[] = [];
    const client = createServerClient(env.API_URL, env.ANON_KEY, {
      cookies: {
        getAll: () => cookies,
        setAll: (values) => {
          for (const value of values) {
            cookies.push({ name: value.name, value: value.value });
          }
        },
      },
    });
    const link = await admin.auth.admin.generateLink({ type: "magiclink", email });
    if (!link.data.properties) throw new Error("Could not sign in local fixture.");
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

    for (const vehicle of [
      {
        end: null,
        start: "2025-06-14T12:00:00Z",
        title: "Current vehicle",
      },
      {
        end: "2024-03-01T12:00:00Z",
        start: "2021-12-24T12:00:00Z",
        title: "Earlier vehicle",
      },
    ]) {
      const saved = await client.rpc("save_vehicle_entry", {
        p_body: "A vehicle chapter.",
        p_collection_names: [],
        p_color: "Green",
        p_date_precision: vehicle.end ? "range" : "day",
        p_entry_id: null,
        p_expected_revision: null,
        p_make: "Memo",
        p_model: "Trail",
        p_model_year: 2025,
        p_occurred_end: vehicle.end,
        p_occurred_label: null,
        p_occurred_start: vehicle.start,
        p_occurred_timezone: "America/Los_Angeles",
        p_tag_names: [],
        p_title: vehicle.title,
      });
      expect(saved.error).toBeNull();
    }

    await page.goto("/vehicles");
    const current = page.getByRole("button", { name: /Current vehicle/ });
    const earlier = page.getByRole("button", { name: /Earlier vehicle/ });
    await expect(current).toBeVisible();
    await expect(earlier).toBeVisible();
    const metrics = await Promise.all(
      [current, earlier].map((card) =>
        card.evaluate((element) => {
          const card = element.getBoundingClientRect();
          const visual = element.firstElementChild!.getBoundingClientRect();
          return {
            leftInset: visual.left - card.left,
            padding: getComputedStyle(element).padding,
            rightInset: card.right - visual.right,
            top: card.top,
            topInset: visual.top - card.top,
          };
        }),
      ),
    );
    expect(Math.abs(metrics[0].top - metrics[1].top)).toBeLessThan(1);
    for (const metric of metrics) {
      expect(metric.padding).toBe("0px");
      expect(metric.leftInset).toBeLessThanOrEqual(1.5);
      expect(metric.rightInset).toBeLessThanOrEqual(1.5);
      expect(metric.topInset).toBeLessThanOrEqual(1.5);
    }
    await page.screenshot({
      caret: "initial",
      fullPage: true,
      path: "/private/tmp/memotrail-vehicle-grid-desktop.png",
    });
    await page.setViewportSize({ height: 844, width: 390 });
    await expect(current).toBeVisible();
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
    ).toBe(true);
    expect(
      await current.evaluate(
        (element) => getComputedStyle(element).padding === "0px",
      ),
    ).toBe(true);
    await page.screenshot({
      caret: "initial",
      fullPage: true,
      path: "/private/tmp/memotrail-vehicle-grid-mobile.png",
    });
  } finally {
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
