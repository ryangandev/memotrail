import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test, type Page } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("The Dashboard greets the signed-in person and supports capture, navigation, and narrow screens", async ({
  context,
  page,
}) => {
  test.setTimeout(120_000);
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
  const owners: string[] = [];
  try {
    await page.goto("/");
    await expect(
      page.getByRole("button", { name: "Continue with Google" }),
    ).toBeVisible();
    await expect(
      page.getByRole("form", { name: "Quick capture", exact: true }),
    ).toHaveCount(0);
    const email = `home-dashboard-${randomUUID()}@memotrail.local`;
    const created = await admin.auth.admin.createUser({
      email,
      email_confirm: true,
    });
    expect(created.error).toBeNull();
    const owner = created.data.user!.id;
    owners.push(owner);
    const outsider = await admin.auth.admin.createUser({
      email: `home-dashboard-other-${randomUUID()}@memotrail.local`,
      email_confirm: true,
    });
    expect(outsider.error).toBeNull();
    owners.push(outsider.data.user!.id);
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
    const signedIn = await client.auth.verifyOtp({
      type: "magiclink",
      token_hash: link.data.properties!.hashed_token,
    });
    expect(signedIn.error).toBeNull();
    await context.addCookies(
      cookies.map((cookie) => ({
        ...cookie,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax" as const,
      })),
    );
    const profile = await client
      .from("profiles")
      .update({ display_name: "Preview Tester" })
      .eq("user_id", owner);
    expect(profile.error).toBeNull();
    const inserted = await admin
      .from("entries")
      .insert([
        {
          owner_id: owner,
          title: "A kept memory",
          body: "A quiet afternoon worth returning to.",
          item_kind: "entry",
          item_subtype: "entry",
          is_first_time: true,
          date_precision: "day",
          occurred_start: "2020-05-12T12:00:00Z",
        },
        {
          owner_id: owner,
          title: "A Chapter underway",
          body: "Still going.",
          item_kind: "entry",
          item_subtype: "chapter",
          is_first_time: false,
          date_precision: "month",
          occurred_start: "2025-01-01T12:00:00Z",
        },
        {
          owner_id: owner,
          title: "A longer kept entry ".repeat(6),
          body: "Long content that must not expand the recent row. ".repeat(30),
          item_kind: "entry",
          item_subtype: "entry",
          is_first_time: false,
          date_precision: "unknown",
        },
        {
          owner_id: owner,
          title: null,
          body: "Waiting for a little context",
          item_kind: "entry",
          item_subtype: "entry",
          is_first_time: false,
          date_precision: "unknown",
        },
        {
          owner_id: owners[1],
          title: "Other owner private memory",
          body: "Must never appear",
          item_kind: "entry",
          item_subtype: "entry",
          is_first_time: false,
          date_precision: "day",
          occurred_start: "2020-05-12T12:00:00Z",
        },
      ])
      .select("id,title,owner_id");
    expect(inserted.error).toBeNull();
    const keptId = inserted.data!.find(
      (entry) => entry.title === "A kept memory",
    )!.id;
    const pendingId = inserted.data!.find(
      (entry) => entry.owner_id === owner && !entry.title,
    )!.id;

    {
      await page.setViewportSize({ width: 1440, height: 1000 });
      await page.goto("/");
      const nav = page.getByRole("navigation", {
        name: "Primary navigation",
        exact: true,
      });
      await expect(
        nav.getByRole("link", { name: "Dashboard", exact: true }),
      ).toHaveAttribute("aria-current", "page");
      // A serif greeting with no trailing period.
      await expect(page.getByRole("heading", { level: 1 })).toHaveText(
        /^Good (morning|afternoon|evening), Preview$/,
      );
      const recent = page.getByRole("region", { name: "Recent", exact: true });
      await expect(recent).toContainText("A kept memory");
      // An untitled capture is simply kept, titled by its date, never queued for review.
      const untitledRow = recent.getByRole("link", { name: "Undated entry" });
      await expect(untitledRow).toContainText("Waiting for a little context");
      await expect(
        page.getByRole("region", { name: "Needs organizing" }),
      ).toHaveCount(0);
      await expect(page.getByRole("link", { name: /To organize/ })).toHaveCount(
        0,
      );
      const now = page.getByRole("region", { name: "Now", exact: true });
      await expect(now).toContainText("A Chapter underway");
      await expect(
        now.getByRole("link", { name: /A Chapter underway/ }),
      ).toHaveAttribute("href", /^\/items\//);
      const past = page.getByRole("region", {
        name: "From your past",
        exact: true,
      });
      await expect(past).toContainText("A kept memory");
      await expect(page.getByText("Other owner private memory")).toHaveCount(0);
      await expect(
        page.getByRole("textbox", { name: "Entry text", exact: true }),
      ).toBeEnabled();
      await expect(page.getByRole("main").getByRole("alert")).toHaveCount(0);
      await expect(nav.locator('a[href^="/home-ideas/"]')).toHaveCount(0);
      await expect(
        page.getByRole("navigation", { name: "Home design previews" }),
      ).toHaveCount(0);
      // The dock holds Search alone here, since the composer is already on the page.
      await expect(
        page.getByRole("button", { name: "Search everything", exact: true }),
      ).toBeVisible();
      await expect(page.getByRole("button", { name: "New entry" })).toHaveCount(
        0,
      );
      const hero = page.locator("[data-ui-page-header]:visible");
      const glance = page.getByRole("navigation", {
        name: "Your Library at a glance",
      });
      // The counts lead to their places; zero counts are left out.
      await expect(glance.getByRole("link")).toHaveText([
        "4 Entries",
        "1 Chapter now",
        "1 First Time",
      ]);
      await expect(
        glance.getByRole("link", { name: "4 Entries" }),
      ).toHaveAttribute("href", "/library");
      await expect(
        glance.getByRole("link", { name: "1 First Time" }),
      ).toHaveAttribute("href", "/first-times");
      const capture = page.getByRole("form", {
        name: "Quick capture",
        exact: true,
      });
      for (const width of [1440, 989]) {
        await page.setViewportSize({ width, height: 1000 });
        await settleLayout(page);
        // The composer and Recent share one column.
        await expect
          .poll(async () => {
            const [captureBox, recentBox] = await Promise.all([
              capture.boundingBox(),
              recent.boundingBox(),
            ]);
            return (
              Math.abs(captureBox!.x - recentBox!.x) +
              Math.abs(captureBox!.width - recentBox!.width)
            );
          })
          .toBeLessThan(1);
        const [heroBox, captureBox, nowBox, pastBox, recentBox] =
          await Promise.all([
            hero.boundingBox(),
            capture.boundingBox(),
            now.boundingBox(),
            past.boundingBox(),
            recent.boundingBox(),
          ]);
        expect(captureBox!.y).toBeGreaterThanOrEqual(
          heroBox!.y + heroBox!.height,
        );
        // Now and the memory sit side by side below the composer, equal in width.
        expect(nowBox!.y).toBeGreaterThanOrEqual(
          captureBox!.y + captureBox!.height,
        );
        expect(Math.abs(pastBox!.y - nowBox!.y)).toBeLessThan(1);
        expect(nowBox!.x + nowBox!.width).toBeLessThanOrEqual(pastBox!.x);
        expect(Math.abs(pastBox!.width - nowBox!.width)).toBeLessThan(1);
        expect(recentBox!.y).toBeGreaterThanOrEqual(
          Math.max(nowBox!.y + nowBox!.height, pastBox!.y + pastBox!.height),
        );
        // A long title and excerpt stay on one line each, so no row grows.
        const rowHeights = await recent
          .locator("[data-ui-entry-row]")
          .evaluateAll((rows) =>
            rows.map((row) => row.getBoundingClientRect().height),
          );
        expect(rowHeights.length).toBeGreaterThan(1);
        expect(Math.max(...rowHeights)).toBeLessThan(120);
        if (width === 989) {
          await page.screenshot({
            path: test.info().outputPath("memotrail-home-dashboard-medium.png"),
            animations: "disabled",
          });
        }
      }
      await page.setViewportSize({ width: 1440, height: 1000 });
      // Let the page paint at the new size so the screenshot holds no stale tiles.
      await page.evaluate(
        () =>
          new Promise((resolve) =>
            requestAnimationFrame(() => requestAnimationFrame(resolve)),
          ),
      );
      await page.screenshot({
        path: test.info().outputPath(`memotrail-home-dashboard-desktop.png`),
        animations: "disabled",
      });
      for (const width of [834, 390]) {
        await page.setViewportSize({ width, height: 844 });
        await settleLayout(page);
        await expect
          .poll(() =>
            page.evaluate(
              () => document.documentElement.scrollWidth <= innerWidth,
            ),
          )
          .toBe(true);
        // One column: Now, then the memory, each below the composer.
        const [captureBox, nowBox, pastBox] = await Promise.all([
          capture.boundingBox(),
          now.boundingBox(),
          past.boundingBox(),
        ]);
        expect(nowBox!.y).toBeGreaterThanOrEqual(
          captureBox!.y + captureBox!.height,
        );
        expect(pastBox!.y).toBeGreaterThanOrEqual(nowBox!.y + nowBox!.height);
        const save = page.getByRole("button", {
          name: "Save",
          exact: true,
        });
        await expect(save).toBeVisible();
        const box = await save.boundingBox();
        expect(box!.x).toBeGreaterThanOrEqual(0);
        expect(box!.x + box!.width).toBeLessThanOrEqual(width);
        if (width === 390) {
          // Search rests a gap above the phone tab bar rather than behind it.
          const [searchBox, tabBarBox] = await Promise.all([
            page
              .getByRole("button", { name: "Search everything", exact: true })
              .boundingBox(),
            page
              .getByRole("navigation", { name: "Mobile navigation" })
              .boundingBox(),
          ]);
          expect(tabBarBox!.y - (searchBox!.y + searchBox!.height)).toBeCloseTo(
            12,
            0,
          );
          await page.screenshot({
            path: test.info().outputPath(`memotrail-home-dashboard-mobile.png`),
            animations: "disabled",
          });
        }
      }
      await page.setViewportSize({ width: 320, height: 700 });
      // The formatting toolbar appears once the writer starts, and must still fit.
      await page
        .getByRole("textbox", { name: "Entry text", exact: true })
        .click();
      const formattingToolbar = page.getByRole("toolbar", {
        name: "Text formatting",
      });
      await expect(formattingToolbar).toBeVisible();
      await expect
        .poll(() =>
          formattingToolbar.evaluate((element) =>
            Math.round(element.scrollWidth - element.clientWidth),
          ),
        )
        .toBeLessThanOrEqual(1);
    }

    await page.setViewportSize({ width: 1440, height: 1000 });
    await page
      .getByRole("navigation", { name: "Primary navigation", exact: true })
      .getByRole("link", { name: "Dashboard", exact: true })
      .click();
    await expect(page).toHaveURL("/");
    await page
      .getByRole("textbox", { name: "Entry text", exact: true })
      .fill("Captured from Home");
    await page.getByRole("button", { name: "Save", exact: true }).click();
    await expect(
      page
        .locator("[data-sonner-toast]")
        .filter({ hasText: /saved|captured/i })
        .first(),
    ).toBeVisible();
    await expect(
      page.getByRole("region", { name: "Recent", exact: true }),
    ).toContainText("Captured from Home");

    await page
      .getByRole("region", { name: "Recent", exact: true })
      .getByRole("link", { name: "Undated entry" })
      .click();
    await expect(page).toHaveURL(`/items/${pendingId}`);
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(
      "Undated entry",
    );
    await expect(
      page.getByRole("button", { name: "Edit Entry", exact: true }),
    ).toBeVisible();
    await page.goto("/");
    await page
      .getByRole("region", { name: "Recent", exact: true })
      .getByRole("link", { name: "A kept memory" })
      .click();
    await expect(page).toHaveURL(`/items/${keptId}`);
    await expect(
      page.getByRole("heading", { name: "A kept memory", exact: true }),
    ).toBeVisible();
    for (const removed of [
      "data-ribbon",
      "split-focus",
      "ledger-column",
      "context-rail",
      "command-center",
      "does-not-exist",
    ]) {
      await page.goto(`/home-ideas/${removed}`);
      await expect(
        page.getByRole("heading", { name: "Page not found" }),
      ).toBeVisible();
    }
  } finally {
    for (const owner of owners) await admin.auth.admin.deleteUser(owner);
  }
});

/**
 * Waits for the transitions a resize starts, such as the sidebar easing to its
 * new width. Each bounding box is read separately, so boxes read while the
 * layout still moves come from different frames.
 */
async function settleLayout(page: Page) {
  await page.evaluate(() =>
    Promise.all(
      document
        .getAnimations()
        .filter((animation) => animation instanceof CSSTransition)
        .map((animation) => animation.finished.catch(() => undefined)),
    ),
  );
}
