import type { BrowserContext, Page } from "@playwright/test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { clickUnlessSynced } from "./helpers/capture-sync";
import { test, expect } from "./helpers/workspace-test";

// Pending captures belong to the signed-in workspace, not to whichever composer
// happens to be mounted: they sync from any page, once per tab, and once across tabs.

test("a capture queued offline on the Dashboard syncs after moving to Library", async ({
  context,
  page,
  workspace,
}) => {
  test.setTimeout(120_000);
  await page.goto("/");
  const composer = page
    .locator("main")
    .getByRole("form", { name: "Quick capture", exact: true });
  await expect(
    composer.getByRole("textbox", { name: "Entry text", exact: true }),
  ).toBeVisible();
  await page.waitForLoadState("networkidle");

  await context.setOffline(true);
  await composer
    .getByRole("textbox", { name: "Entry text", exact: true })
    .fill("Offline on the Dashboard");
  await composer
    .getByRole("button", { name: "Save to Inbox", exact: true })
    .click();
  await expect(
    page.locator("main").getByRole("heading", {
      name: "Pending sync",
      exact: true,
    }),
  ).toBeVisible();
  const indicator = pendingIndicator(page);
  await expect(indicator).toHaveText("1 pending");

  // The browser reconnects before MemoTrail is reachable, so the Dashboard's
  // attempt fails and the capture is still waiting when the person moves on.
  await setMemoTrailReachable(page, false);
  await context.setOffline(false);
  await page
    .getByRole("navigation", { name: "Primary navigation" })
    .getByRole("link", { name: "Library", exact: true })
    .click();
  await expect(page).toHaveURL(/\/library$/);
  await expect(
    page.locator("main").getByRole("form", { name: "Quick capture" }),
  ).toHaveCount(0);
  await expect(indicator).toHaveText("1 pending");

  await reconnect(context, page);
  await expectEntryCount(workspace.client, "Offline on the Dashboard", 1);
  await expect(indicator).toHaveCount(0);
});

test("a capture keeps retrying while online until MemoTrail can be reached", async ({
  page,
  workspace,
}) => {
  test.setTimeout(120_000);
  await page.goto("/library");
  await page.waitForLoadState("networkidle");
  const attempts = countCaptureSyncAttempts(page);

  // The browser reports a connection throughout, so no online event will
  // announce that MemoTrail is back.
  await setMemoTrailReachable(page, false);
  await page.getByRole("button", { name: "New entry", exact: true }).click();
  const dialog = page.getByRole("dialog", { name: "What’s on your mind?" });
  await dialog
    .getByRole("textbox", { name: "Entry text", exact: true })
    .fill("Retried while online");
  await dialog
    .getByRole("button", { name: "Save to Inbox", exact: true })
    .click();
  await expect(
    dialog.getByRole("heading", { name: "Pending sync", exact: true }),
  ).toBeVisible();
  await dialog.getByRole("button", { name: "Close quick capture" }).click();
  await expect(pendingIndicator(page)).toHaveText("1 pending");
  await expect
    .poll(() => attempts.for("Retried while online"), { timeout: 10_000 })
    .toBeGreaterThanOrEqual(2);

  await setMemoTrailReachable(page, true);
  await expectEntryCount(workspace.client, "Retried while online", 1);
  await expect(pendingIndicator(page)).toHaveCount(0);
});

test("a capture from a closed Quick Capture syncs when the connection returns", async ({
  context,
  page,
  workspace,
}) => {
  test.setTimeout(120_000);
  await page.goto("/library");
  await page.waitForLoadState("networkidle");
  await page.getByRole("button", { name: "New entry", exact: true }).click();
  const dialog = page.getByRole("dialog", { name: "What’s on your mind?" });
  await expect(
    dialog.getByRole("textbox", { name: "Entry text", exact: true }),
  ).toBeVisible();

  await context.setOffline(true);
  await dialog
    .getByRole("textbox", { name: "Entry text", exact: true })
    .fill("Offline from Quick Capture");
  await dialog
    .getByRole("button", { name: "Save to Inbox", exact: true })
    .click();
  await expect(
    dialog.getByRole("heading", { name: "Pending sync", exact: true }),
  ).toBeVisible();
  await dialog.getByRole("button", { name: "Close quick capture" }).click();
  await expect(dialog).toBeHidden();
  await expect(pendingIndicator(page)).toHaveText("1 pending");

  await context.setOffline(false);
  await expectEntryCount(workspace.client, "Offline from Quick Capture", 1);
  await expect(pendingIndicator(page)).toHaveCount(0);
});

test("the header pending indicator syncs and lists captures waiting on this device", async ({
  page,
  workspace,
}) => {
  test.setTimeout(120_000);
  await page.goto("/people");
  await page.waitForLoadState("networkidle");
  const attempts = countCaptureSyncAttempts(page);

  await setMemoTrailReachable(page, false);
  await page.getByRole("button", { name: "New entry", exact: true }).click();
  const capture = page.getByRole("dialog", { name: "What’s on your mind?" });
  await capture
    .getByRole("textbox", { name: "Entry text", exact: true })
    .fill("Waiting for MemoTrail");
  await capture
    .getByRole("button", { name: "Save to Inbox", exact: true })
    .click();
  await expect(
    capture.getByRole("heading", { name: "Pending sync", exact: true }),
  ).toBeVisible();
  await capture.getByRole("button", { name: "Close quick capture" }).click();
  await expect(capture).toBeHidden();

  const indicator = page
    .locator("main > header")
    .getByRole("button", { name: "1 pending", exact: true });
  await expect(indicator).toHaveAttribute("aria-haspopup", "dialog");
  const attemptsBeforeOpening = attempts.for("Waiting for MemoTrail");
  await indicator.click();
  const pending = page.getByRole("dialog", { name: "Pending sync" });
  await expect(pending).toBeVisible();
  await expect
    .poll(() => attempts.for("Waiting for MemoTrail"))
    .toBeGreaterThan(attemptsBeforeOpening);
  await expect(pending.getByRole("article")).toHaveCount(1);
  await expect(pending.getByRole("article")).toContainText(
    "Waiting for MemoTrail",
  );
  await expect(pending.getByRole("article")).toContainText("On this device");
  await expect(pending.getByRole("alert")).toHaveText(
    "Saved on this device. MemoTrail will retry when you are online.",
  );
  await expect(
    pending.getByRole("button", { name: "Retry now", exact: true }),
  ).toBeEnabled();
  await page.screenshot({
    animations: "disabled",
    path: "/private/tmp/memotrail-pending-sync-dialog.png",
  });
  await pending
    .getByRole("button", { name: "Close Pending sync", exact: true })
    .click();
  await expect(pending).toBeHidden();
  await expect(indicator).toBeFocused();

  await setMemoTrailReachable(page, true);
  await clickUnlessSynced(indicator);
  await expectEntryCount(workspace.client, "Waiting for MemoTrail", 1);
  await expect(pending).toBeHidden();
  await expect(indicator).toHaveCount(0);
  await expect(
    page.getByText("Saved to Inbox.", { exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole("link", { name: "Open Inbox, 1 item", exact: true }),
  ).toBeVisible();
});

test("the Dashboard composer and Quick Capture send each queued capture once", async ({
  context,
  page,
  workspace,
}) => {
  test.setTimeout(120_000);
  await page.goto("/");
  const composer = page
    .locator("main")
    .getByRole("form", { name: "Quick capture", exact: true });
  await expect(
    composer.getByRole("textbox", { name: "Entry text", exact: true }),
  ).toBeVisible();
  await page.waitForLoadState("networkidle");
  const attempts = countCaptureSyncAttempts(page);

  await context.setOffline(true);
  await composer
    .getByRole("textbox", { name: "Entry text", exact: true })
    .fill("Once from the Dashboard");
  await composer
    .getByRole("button", { name: "Save to Inbox", exact: true })
    .click();
  await expect(pendingIndicator(page)).toHaveText("1 pending");
  await page.getByRole("button", { name: "New entry", exact: true }).click();
  const dialog = page.getByRole("dialog", { name: "What’s on your mind?" });
  await dialog
    .getByRole("textbox", { name: "Entry text", exact: true })
    .fill("Once from Quick Capture");
  await dialog
    .getByRole("button", { name: "Save to Inbox", exact: true })
    .click();
  await expect(pendingIndicator(page)).toHaveText("2 pending");
  await expect(
    dialog.getByRole("heading", { name: "Pending sync", exact: true }),
  ).toBeVisible();
  await expect(dialog.getByRole("article")).toHaveCount(2);
  const offlineAttempts = {
    dashboard: attempts.for("Once from the Dashboard"),
    quickCapture: attempts.for("Once from Quick Capture"),
  };

  await context.setOffline(false);
  await expectEntryCount(workspace.client, "Once from the Dashboard", 1);
  await expectEntryCount(workspace.client, "Once from Quick Capture", 1);
  await expect(pendingIndicator(page)).toHaveCount(0);
  await expect(dialog.getByRole("article")).toHaveCount(0);
  await page.waitForLoadState("networkidle");
  expect(attempts.for("Once from the Dashboard")).toBe(
    offlineAttempts.dashboard + 1,
  );
  expect(attempts.for("Once from Quick Capture")).toBe(
    offlineAttempts.quickCapture + 1,
  );
  await expect(page.getByText("Saved to Inbox.", { exact: true })).toHaveCount(
    1,
  );
});

test("two tabs send each queued capture once", async ({
  context,
  page,
  workspace,
}) => {
  test.setTimeout(120_000);
  const other = await context.newPage();
  await page.goto("/library");
  await other.goto("/people");
  await page.waitForLoadState("networkidle");
  await other.waitForLoadState("networkidle");
  const attempts = [
    countCaptureSyncAttempts(page),
    countCaptureSyncAttempts(other),
  ];

  await context.setOffline(true);
  await page.getByRole("button", { name: "New entry", exact: true }).click();
  const dialog = page.getByRole("dialog", { name: "What’s on your mind?" });
  await dialog
    .getByRole("textbox", { name: "Entry text", exact: true })
    .fill("Once across tabs");
  await dialog
    .getByRole("button", { name: "Save to Inbox", exact: true })
    .click();
  await dialog.getByRole("button", { name: "Close quick capture" }).click();
  await expect(pendingIndicator(page)).toHaveText("1 pending");
  // localStorage is shared, so the other tab shows the same waiting capture.
  await expect(pendingIndicator(other)).toHaveText("1 pending");
  const offlineAttempts = attempts.reduce(
    (total, tab) => total + tab.for("Once across tabs"),
    0,
  );

  await context.setOffline(false);
  await expectEntryCount(workspace.client, "Once across tabs", 1);
  await expect(pendingIndicator(page)).toHaveCount(0);
  await expect(pendingIndicator(other)).toHaveCount(0);
  // Both tabs count the synced capture in Inbox, not only the one that sent it.
  for (const tab of [page, other])
    await expect(
      tab.getByRole("link", { name: "Open Inbox, 1 item", exact: true }),
    ).toBeVisible();
  await page.waitForLoadState("networkidle");
  await other.waitForLoadState("networkidle");
  expect(
    attempts.reduce((total, tab) => total + tab.for("Once across tabs"), 0),
  ).toBe(offlineAttempts + 1);
  await other.close();
});

function pendingIndicator(page: Page) {
  return page.locator("main > header").getByText(/^\d+ pending$/);
}

/** Counts server action requests that carry a queued capture's text. */
function countCaptureSyncAttempts(page: Page) {
  const bodies: string[] = [];
  page.on("request", (request) => {
    if (request.method() === "POST" && request.headers()["next-action"])
      bodies.push(request.postData() ?? "");
  });
  return {
    for: (text: string) => bodies.filter((body) => body.includes(text)).length,
  };
}

/** Fails server actions as if MemoTrail could not be reached. */
async function setMemoTrailReachable(page: Page, reachable: boolean) {
  if (reachable) {
    await page.unroute("**/*");
    return;
  }
  await page.route("**/*", (route) =>
    route.request().method() === "POST" &&
    route.request().headers()["next-action"]
      ? route.abort("internetdisconnected")
      : route.continue(),
  );
}

/** Restores MemoTrail and lets the browser announce that it is online again. */
async function reconnect(context: BrowserContext, page: Page) {
  await context.setOffline(true);
  await setMemoTrailReachable(page, true);
  await context.setOffline(false);
}

async function expectEntryCount(
  client: SupabaseClient,
  body: string,
  count: number,
) {
  await expect
    .poll(
      async () =>
        (await client.from("entries").select("id").eq("body", body)).data
          ?.length,
      { timeout: 20_000 },
    )
    .toBe(count);
}
