import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";

test("Home uses the signed-in archive and support capture, navigation, and narrow screens", async ({
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
          inbox_status: "organized",
          item_kind: "entry",
          item_subtype: "entry",
          date_precision: "day",
          occurred_start: "2020-05-12T12:00:00Z",
        },
        {
          owner_id: owner,
          title: "A longer kept entry ".repeat(6),
          body: "Long content that must not expand the recent row. ".repeat(30),
          inbox_status: "organized",
          item_kind: "entry",
          item_subtype: "entry",
          date_precision: "unknown",
        },
        {
          owner_id: owner,
          title: null,
          body: "Waiting for a little context",
          inbox_status: "unreviewed",
          item_kind: "entry",
          item_subtype: "entry",
          date_precision: "unknown",
        },
        {
          owner_id: owners[1],
          title: "Other owner private memory",
          body: "Must never appear",
          inbox_status: "organized",
          item_kind: "entry",
          item_subtype: "entry",
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
      await expect(page.getByRole("heading", { level: 1 })).toContainText(
        "Preview",
      );
      await expect(
        page.getByRole("region", { name: "Recent Entries", exact: true }),
      ).toContainText("A kept memory");
      await expect(
        page.getByRole("region", { name: "Ready to organize", exact: true }),
      ).toContainText("Waiting for a little context");
      await expect(
        page.getByRole("region", { name: "A memory for today", exact: true }),
      ).toContainText("A kept memory");
      await expect(page.getByText("Other owner private memory")).toHaveCount(0);
      await expect(
        page.getByRole("textbox", { name: "Entry text", exact: true }),
      ).toBeEnabled();
      await expect(page.getByRole("main").getByRole("alert")).toHaveCount(0);
      await expect(nav.locator('a[href^="/home-ideas/"]')).toHaveCount(0);
      await expect(
        page.getByRole("navigation", { name: "Home design previews" }),
      ).toHaveCount(0);
      const hero = page.locator("[data-ui-page-header]:visible");
      const metrics = page.getByRole("navigation", {
        name: "Your archive at a glance",
      });
      const capture = page.getByRole("form", {
        name: "Quick capture",
        exact: true,
      });
      const inboxPanel = page
        .getByRole("region", { name: "Ready to organize", exact: true })
        .locator("..");
      for (const width of [1440, 989]) {
        await page.setViewportSize({ width, height: 1000 });
        await expect
          .poll(async () => {
            const [left, right] = await Promise.all([
              capture.boundingBox(),
              inboxPanel.boundingBox(),
            ]);
            return (
              Math.abs(left!.height - right!.height) +
              Math.abs(left!.y - right!.y)
            );
          })
          .toBeLessThan(2);
        const [heroBox, metricsBox, captureBox, inboxBox] = await Promise.all([
          hero.boundingBox(),
          metrics.boundingBox(),
          capture.boundingBox(),
          inboxPanel.boundingBox(),
        ]);
        expect(metricsBox!.y).toBeGreaterThanOrEqual(
          heroBox!.y + heroBox!.height,
        );
        expect(inboxBox!.x).toBeGreaterThan(captureBox!.x);
        const [memoryBox, chaptersBox, recentBox] = await Promise.all([
          page
            .getByRole("region", { name: "A memory for today", exact: true })
            .boundingBox(),
          page
            .getByRole("region", { name: "Current chapters", exact: true })
            .boundingBox(),
          page
            .getByRole("region", { name: "Recent Entries", exact: true })
            .boundingBox(),
        ]);
        expect(Math.abs(memoryBox!.height - chaptersBox!.height)).toBeLessThan(
          1,
        );
        expect(Math.abs(memoryBox!.y - chaptersBox!.y)).toBeLessThan(1);
        expect(Math.abs(recentBox!.width - metricsBox!.width)).toBeLessThan(1);
        expect(recentBox!.y).toBeGreaterThanOrEqual(
          memoryBox!.y + memoryBox!.height,
        );
        const rowHeights = await page
          .getByRole("region", { name: "Recent Entries", exact: true })
          .locator("a:has(article)")
          .evaluateAll((rows) =>
            rows.map((row) => row.getBoundingClientRect().height),
          );
        expect(rowHeights.length).toBeGreaterThan(1);
        expect(Math.max(...rowHeights) - Math.min(...rowHeights)).toBeLessThan(
          1,
        );

        expect(
          await metrics.getByRole("link").evaluateAll((links) =>
            links.every((link) => {
              const value = link
                .querySelector("strong")!
                .getBoundingClientRect();
              const label = link.querySelector("span")!.getBoundingClientRect();
              return (
                label.left >= value.right &&
                label.top < value.bottom &&
                label.bottom > value.top
              );
            }),
          ),
        ).toBe(true);
        const metricRows = await metrics
          .getByRole("link")
          .evaluateAll((links) =>
            links.map((link) => Math.round(link.getBoundingClientRect().top)),
          );
        const metricLayout = await metrics.evaluate((element) => {
          const [first, second] = Array.from(element.querySelectorAll("a"));
          return {
            borderRadius: getComputedStyle(element).borderRadius,
            cellBorderRadius: getComputedStyle(first).borderRadius,
            firstCellRight: first.getBoundingClientRect().right,
            secondCellLeft: second.getBoundingClientRect().left,
          };
        });
        expect(metricLayout.borderRadius).not.toBe("0px");
        expect(metricLayout.cellBorderRadius).toBe("0px");
        expect(
          Math.abs(metricLayout.firstCellRight - metricLayout.secondCellLeft),
        ).toBeLessThan(1);
        expect(metricRows.slice(0, 3)).toEqual([
          metricRows[0],
          metricRows[0],
          metricRows[0],
        ]);
        if (width === 1440) {
          expect(metricRows[4]).toBe(metricRows[0]);
        } else {
          expect(metricRows[3]).toBeGreaterThan(metricRows[0]);
          expect(metricRows[4]).toBe(metricRows[3]);
          await page.screenshot({
            path: "/tmp/memotrail-home-dashboard-medium.png",
            animations: "disabled",
          });
        }
      }
      await page.setViewportSize({ width: 1440, height: 1000 });
      await page.screenshot({
        path: `/tmp/memotrail-home-dashboard-desktop.png`,
        animations: "disabled",
      });
      for (const width of [834, 390]) {
        await page.setViewportSize({ width, height: 844 });
        await expect
          .poll(() =>
            page.evaluate(
              () => document.documentElement.scrollWidth <= innerWidth,
            ),
          )
          .toBe(true);
        const [captureBox, inboxBox] = await Promise.all([
          capture.boundingBox(),
          inboxPanel.boundingBox(),
        ]);
        expect(inboxBox!.y).toBeGreaterThanOrEqual(
          captureBox!.y + captureBox!.height,
        );
        expect(Math.abs(inboxBox!.x - captureBox!.x)).toBeLessThan(1);
        const save = page.getByRole("button", {
          name: "Save to Inbox",
          exact: true,
        });
        await expect(save).toBeVisible();
        const box = await save.boundingBox();
        expect(box!.x).toBeGreaterThanOrEqual(0);
        expect(box!.x + box!.width).toBeLessThanOrEqual(width);
        if (width === 390)
          await page.screenshot({
            path: `/tmp/memotrail-home-dashboard-mobile.png`,
            animations: "disabled",
          });
      }
      await page.setViewportSize({ width: 320, height: 700 });
      const formattingToolbar = page.getByRole("toolbar", {
        name: "Text formatting",
      });
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
    await page
      .getByRole("button", { name: "Save to Inbox", exact: true })
      .click();
    await expect(
      page
        .locator("[data-sonner-toast]")
        .filter({ hasText: /saved|captured/i })
        .first(),
    ).toBeVisible();
    await expect(
      page.getByRole("region", { name: "Ready to organize", exact: true }),
    ).toContainText("Captured from Home");
    await expect(
      page.getByRole("region", { name: "Recent Entries", exact: true }),
    ).not.toContainText("Captured from Home");
    const captured = await client
      .from("entries")
      .select("inbox_status")
      .eq("owner_id", owner)
      .eq("body", "Captured from Home")
      .single();
    expect(captured.error).toBeNull();
    expect(captured.data!.inbox_status).toBe("unreviewed");

    await page
      .getByRole("link", {
        name: "Organize Waiting for a little context",
        exact: true,
      })
      .click();
    await expect(page).toHaveURL(`/inbox?entry=${pendingId}`);
    await expect(
      page.getByRole("dialog", { name: "Review Entry" }),
    ).toBeVisible();
    await page.goto("/");
    await page
      .getByRole("region", { name: "Recent Entries", exact: true })
      .getByRole("link")
      .filter({ hasText: "A kept memory" })
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
        page.getByText("This page could not be found."),
      ).toBeVisible();
    }
  } finally {
    for (const owner of owners) await admin.auth.admin.deleteUser(owner);
  }
});
