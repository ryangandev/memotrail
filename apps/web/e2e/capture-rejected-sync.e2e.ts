import type { Locator, Page } from "@playwright/test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { clickUnlessSynced } from "./helpers/capture-sync";
import { isTopmostAtCenter } from "./helpers/hit-test";
import { test, expect } from "./helpers/workspace-test";

// A capture MemoTrail will never accept is not an offline capture: it is kept
// with its content for the person, never retried, and never holds back the
// captures saved after it. A pasted NUL character passes every client check,
// but Postgres text cannot store it, so the server rejects it for real.

const rejectedText = "Pasted from a terminal \u0000 log";
const rejectedPrefix = "Pasted from a terminal";
const offlineMessage =
  "Saved on this device. MemoTrail will retry when you are online.";
const rejectedMessage =
  "MemoTrail cannot accept this Entry, so it will not sync. Copy its text to keep it, then discard it.";

test("a rejected capture can be copied and discarded while later captures sync", async ({
  context,
  page,
  workspace,
}) => {
  test.setTimeout(180_000);
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  const composer = await openDashboardComposer(page);
  const attempts = countCaptureSyncAttempts(page);

  await saveCapture(page, composer, rejectedText);
  await expect(
    page.getByText(
      "MemoTrail did not accept 1 Entry. Review it in Pending sync.",
      { exact: true },
    ),
  ).toBeVisible({ timeout: 60_000 });
  const pending = page.locator("main").getByRole("region", {
    name: "Pending sync",
  });
  const rejected = pending.getByRole("article");
  await expect(rejected).toHaveCount(1);
  await expect(rejected).toContainText("Not accepted");
  await expect(rejected).toContainText(rejectedMessage);
  await expect(composer).not.toContainText(offlineMessage);
  // Captures MemoTrail did not accept are never retried.
  await expect(
    pending.getByRole("button", { name: "Retry now", exact: true }),
  ).toHaveCount(0);
  await expect(pendingIndicator(page)).toHaveText("1 not accepted");

  // A later capture is not held back behind the rejected one.
  await saveCapture(page, composer, "A valid later capture");
  await expectEntryCount(workspace.client, "A valid later capture", 1);
  await expect(
    page.getByText("Saved to Library.", { exact: true }),
  ).toBeVisible();
  await expect(rejected).toHaveCount(1);
  expect(attempts.for(rejectedPrefix)).toBe(1);

  // The rejection belongs to this device's queue, so it survives a reload
  // without another attempt.
  await page.reload();
  await expect(
    composer.getByRole("textbox", { name: "Entry text", exact: true }),
  ).toBeVisible({ timeout: 90_000 });
  await expect(rejected).toContainText(rejectedMessage);
  await page.waitForLoadState("networkidle");
  expect(attempts.for(rejectedPrefix)).toBe(1);

  await rejected
    .getByRole("button", { name: "Copy text", exact: true })
    .click();
  await expect(page.getByText("Text copied.", { exact: true })).toBeVisible();
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(
    rejectedText,
  );

  // Quick Capture is a native modal dialog in the top layer, so the shared
  // confirmation it asks for must stack above it and stay interactive.
  await page.getByRole("button", { name: "New entry", exact: true }).click();
  const quickCapture = page.getByRole("dialog", {
    name: "What’s on your mind?",
    exact: true,
  });
  const quickDiscard = quickCapture
    .getByRole("region", { name: "Pending sync" })
    .getByRole("button", { name: "Discard", exact: true });
  await quickDiscard.click();
  const confirmation = page.getByRole("dialog", {
    name: "Discard this pending Entry?",
  });
  const cancel = confirmation.getByRole("button", { name: "Cancel" });
  await expect(cancel).toBeFocused();
  expect(await isTopmostAtCenter(cancel)).toBe(true);
  // Escape dismisses only the confirmation and returns focus to Discard.
  await page.keyboard.press("Escape");
  await expect(confirmation).toBeHidden();
  await expect(quickCapture).toBeVisible();
  await expect(quickDiscard).toBeFocused();
  await quickDiscard.click();
  await cancel.click();
  await expect(confirmation).toBeHidden();
  await expect(quickDiscard).toBeFocused();
  await quickCapture
    .getByRole("button", { name: "Close quick capture" })
    .click();
  await expect(quickCapture).not.toBeVisible();

  // The header lists it apart from waiting captures and discards it after
  // confirmation, with its queued copy.
  await pendingIndicator(page).click();
  const dialog = page.getByRole("dialog", { name: "Pending sync" });
  await expect(dialog).toBeVisible();
  await expect(dialog).toContainText(
    "MemoTrail did not accept 1 Entry; copy what you want to keep, then discard it.",
  );
  await expect(
    dialog.getByRole("button", { name: "Retry now", exact: true }),
  ).toHaveCount(0);
  const headerDiscard = dialog.getByRole("button", {
    name: "Discard",
    exact: true,
  });
  await headerDiscard.click();
  await expect(confirmation).toContainText(
    "Its text will be removed from this device. This cannot be undone.",
  );
  await expect(cancel).toBeFocused();
  await cancel.click();
  await expect(confirmation).toBeHidden();
  await expect(headerDiscard).toBeFocused();
  await expect(dialog.getByRole("article")).toHaveCount(1);

  await headerDiscard.click();
  await confirmation
    .getByRole("button", { name: "Discard", exact: true })
    .click();
  await expect(
    page.getByText("Pending Entry discarded.", { exact: true }),
  ).toBeVisible();
  await expect(dialog).toBeHidden();
  await expect(pendingIndicator(page)).toHaveCount(0);
  await expect(pending).toHaveCount(0);
  expect(await queuedCaptures(page, workspace.owner)).toBeNull();
  expect(attempts.for(rejectedPrefix)).toBe(1);
  await expectEntryCount(workspace.client, "A valid later capture", 1);
});

test("an unreachable MemoTrail still reports offline and retries beside a rejected capture", async ({
  page,
  workspace,
}) => {
  test.setTimeout(180_000);
  const composer = await openDashboardComposer(page);
  const attempts = countCaptureSyncAttempts(page);

  await saveCapture(page, composer, rejectedText);
  await expect(pendingIndicator(page)).toHaveText("1 not accepted", {
    timeout: 60_000,
  });

  await setMemoTrailReachable(page, false);
  await saveCapture(page, composer, "Waiting for MemoTrail");
  await expect(composer).toContainText(offlineMessage, { timeout: 60_000 });
  await expect(pendingIndicator(page)).toHaveText("1 pending · 1 not accepted");
  const pending = page.locator("main").getByRole("region", {
    name: "Pending sync",
  });
  await expect(pending.getByRole("article")).toHaveCount(2);
  await expect(pending.getByRole("article").nth(1)).toContainText(
    "On this device",
  );
  await expect(pending.getByRole("article").nth(1)).not.toContainText(
    "Discard",
  );
  // MemoTrail is retried on its own while the browser is online, and only
  // for the capture that is still waiting.
  await expect
    .poll(() => attempts.for("Waiting for MemoTrail"), { timeout: 10_000 })
    .toBeGreaterThanOrEqual(2);
  expect(attempts.for(rejectedPrefix)).toBe(1);

  await setMemoTrailReachable(page, true);
  await clickUnlessSynced(
    pending.getByRole("button", { name: "Retry now", exact: true }),
  );
  await expectEntryCount(workspace.client, "Waiting for MemoTrail", 1);
  await expect(pendingIndicator(page)).toHaveText("1 not accepted");
  await expect(composer).not.toContainText(offlineMessage);
  await page.waitForLoadState("networkidle");
  expect(attempts.for(rejectedPrefix)).toBe(1);
});

test("a saved capture this version cannot read is kept, listed, and discarded only on request", async ({
  context,
  page,
  workspace,
}) => {
  test.setTimeout(180_000);
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  const unreadableText = "Written offline before a rule changed.";
  const composer = await openDashboardComposer(page);
  // A capture that was valid when queued but fails today's checks.
  const unreadable = {
    attachments: [],
    body: unreadableText,
    id: "9b2b6c1e-8f35-4c63-8d57-4a8d1d0a3c11",
    occurredAt: "not a date",
    occurredTimezone: "UTC",
    queuedAt: "2026-09-01T15:00:00.000Z",
    title: null,
    version: 2,
  };
  await page.evaluate(
    ([key, value]) => localStorage.setItem(key, value),
    [
      `memotrail:inbox-queue:${encodeURIComponent(workspace.owner)}`,
      JSON.stringify([unreadable]),
    ],
  );
  await page.reload();
  await expect(
    composer.getByRole("textbox", { name: "Entry text", exact: true }),
  ).toBeVisible({ timeout: 90_000 });

  const indicator = page.locator("main > header").getByText("1 unreadable");
  await expect(indicator).toBeVisible();
  const pending = page.locator("main").getByRole("region", {
    name: "Pending sync",
  });
  const card = pending.getByRole("article");
  await expect(card).toHaveCount(1);
  await expect(card).toContainText("Could not be read");
  await expect(card).toContainText(unreadableText);

  // A later capture syncs, and the unreadable one is still on this device.
  await saveCapture(page, composer, "A valid later capture");
  await expectEntryCount(workspace.client, "A valid later capture", 1);
  await expect(card).toHaveCount(1);
  await page.reload();
  await expect(card).toContainText(unreadableText);

  await card.getByRole("button", { name: "Copy text", exact: true }).click();
  await expect(page.getByText("Text copied.", { exact: true })).toBeVisible();
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(
    unreadableText,
  );

  const discard = card.getByRole("button", { name: "Discard", exact: true });
  await discard.click();
  const confirmation = page.getByRole("dialog", {
    name: "Discard this saved Entry?",
  });
  await confirmation.getByRole("button", { name: "Cancel" }).click();
  await expect(card).toHaveCount(1);
  await discard.click();
  await confirmation
    .getByRole("button", { name: "Discard", exact: true })
    .click();
  await expect(
    page.getByText("Saved Entry discarded.", { exact: true }),
  ).toBeVisible();
  await expect(pending).toHaveCount(0);
  await expect(indicator).toHaveCount(0);
  expect(
    await page.evaluate(
      (owner) =>
        Object.keys(localStorage).filter(
          (key) =>
            key.includes(encodeURIComponent(owner)) &&
            localStorage.getItem(key)?.includes("Written offline"),
        ),
      workspace.owner,
    ),
  ).toEqual([]);
});

async function openDashboardComposer(page: Page) {
  await page.goto("/");
  const composer = page
    .locator("main")
    .getByRole("form", { name: "Quick capture", exact: true });
  await expect(
    composer.getByRole("textbox", { name: "Entry text", exact: true }),
  ).toBeVisible({ timeout: 90_000 });
  await page.waitForLoadState("networkidle");
  return composer;
}

async function saveCapture(page: Page, composer: Locator, text: string) {
  const save = composer.getByRole("button", {
    name: "Save",
    exact: true,
  });
  await expect(save).toBeEnabled({ timeout: 60_000 });
  await composer
    .getByRole("textbox", { name: "Entry text", exact: true })
    .click();
  // Typed like a paste, so the editor keeps every character it receives.
  await page.keyboard.insertText(text);
  await save.click();
}

function pendingIndicator(page: Page) {
  return page
    .locator("main > header")
    .getByText(/^\d+ (pending|not accepted)( · \d+ not accepted)?$/);
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

function queuedCaptures(page: Page, owner: string) {
  return page.evaluate(
    (key) => localStorage.getItem(key),
    `memotrail:inbox-queue:${encodeURIComponent(owner)}`,
  );
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
      { timeout: 30_000 },
    )
    .toBe(count);
}
