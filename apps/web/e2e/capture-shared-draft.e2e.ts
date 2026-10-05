import type { Locator, Page } from "@playwright/test";
import type { SupabaseClient } from "@supabase/supabase-js";
import sharp from "sharp";
import { test, expect } from "./helpers/workspace-test";

// The Dashboard composer and Quick Capture edit one draft: whatever one shows,
// the other shows, and a save or discard in either clears it everywhere.

test("saving in Quick Capture clears the Dashboard composer, so the draft is captured once", async ({
  page,
  workspace,
}) => {
  test.setTimeout(120_000);
  const { dashboard, dashboardEditor, dialog, dialogEditor } =
    await openDashboard(page);

  await dashboardEditor.fill("Shared draft text");
  await expect(dashboard).toContainText("Draft saved on this device.");
  await dashboardEditor.blur();
  await page.keyboard.press("Meta+j");
  await expect(dialogEditor).toBeFocused();
  await expect(dialogEditor).toHaveText("Shared draft text");

  await dialog
    .getByRole("button", { name: "Save to Library", exact: true })
    .click();
  await expect(dialogEditor).toBeEmpty();
  await expectEntryCount(workspace.client, "Shared draft text", 1);
  await dialog.getByRole("button", { name: "Close quick capture" }).click();
  await expect(dialog).toBeHidden();

  await expect.soft(dashboardEditor).toBeEmpty();
  await expect.soft(dashboard).not.toContainText("Draft saved on this device.");
  // A second save of the same composer must not capture the text again.
  await dashboard
    .getByRole("button", { name: "Save to Library", exact: true })
    .click();
  await expect
    .soft(dashboard)
    .toContainText("Write a title, a note, or add a photo before saving.");
  await expect.poll(() => queuedCaptures(page, workspace.owner)).toEqual([]);
  await page.waitForLoadState("networkidle");
  expect(await entryCount(workspace.client, "Shared draft text")).toBe(1);
  // Typing again starts a new draft instead of writing the old text back.
  await dashboardEditor.press("Meta+ArrowRight");
  await dashboardEditor.pressSequentially("Next");
  await expect
    .poll(() => storedDraft(page, workspace.owner))
    .toMatchObject({ body: "Next" });
});

test("typing in either composer shows in the other without moving the caret", async ({
  page,
  workspace,
}) => {
  test.setTimeout(120_000);
  const { dashboard, dashboardEditor, dialog, dialogEditor, trigger } =
    await openDashboard(page);

  await dashboardEditor.fill("Hello world");
  // A shared update from the composer's own keystroke keeps its selection.
  await dashboardEditor.press("Meta+ArrowRight");
  for (let step = 0; step < 5; step++) await dashboardEditor.press("ArrowLeft");
  await dashboardEditor.pressSequentially("big ");
  await expect(dashboardEditor).toHaveText("Hello big world");

  await trigger.click();
  await expect(dialogEditor).toBeFocused();
  await expect(dialogEditor).toHaveText("Hello big world");
  await dialogEditor.press("Meta+ArrowRight");
  await dialogEditor.pressSequentially(" and more");
  // Mid-line, because ProseMirror moves a caret placed at the very start of
  // the document within 200ms of focus back to where it was.
  for (let step = 0; step < 4; step++) await dialogEditor.press("ArrowLeft");
  await dialogEditor.pressSequentially("so much ");
  await expect(dialogEditor).toHaveText("Hello big world and so much more");
  await dialogEditor.press("Meta+a");
  await dialog
    .getByRole("toolbar", { name: "Text formatting" })
    .getByRole("button", { name: "Bold", exact: true })
    .click();
  await expect(dialogEditor.locator("strong")).toHaveText(
    "Hello big world and so much more",
  );
  await dialog.getByRole("button", { name: "Date", exact: true }).click();
  await expect(dialog.getByLabel("Date type")).toBeVisible();
  await dialog.getByRole("button", { name: "Close quick capture" }).click();
  await expect(dialog).toBeHidden();

  await expect(dashboardEditor).toHaveText("Hello big world and so much more");
  await expect(dashboardEditor.locator("strong")).toHaveText(
    "Hello big world and so much more",
  );
  await expect(dashboard.getByLabel("Date type")).toBeVisible();
  await expect(
    dashboard.getByRole("button", { name: "Custom date", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await expect
    .poll(() => storedDraft(page, workspace.owner))
    .toMatchObject({
      body: "Hello big world and so much more",
      bodyRich: { text: "Hello big world and so much more" },
    });
});

test("discarding a draft in one composer clears it in the other", async ({
  page,
  workspace,
}) => {
  test.setTimeout(120_000);
  const { dashboard, dashboardEditor, dialog, dialogEditor, trigger } =
    await openDashboard(page);

  await dashboardEditor.fill("A thought to let go");
  await dashboard.getByRole("button", { name: "Date", exact: true }).click();
  await expect(dashboard.getByLabel("Date type")).toBeVisible();
  await trigger.click();
  await expect(dialogEditor).toHaveText("A thought to let go");
  await expect(dialog.getByLabel("Date type")).toBeVisible();

  await dialogEditor.press("Meta+a");
  await dialogEditor.press("Backspace");
  await dialog
    .getByRole("button", { name: "Use capture time", exact: true })
    .click();
  await expect(dialogEditor).toBeEmpty();
  await expect(dialog).not.toContainText("Draft saved on this device.");
  await dialog.getByRole("button", { name: "Close quick capture" }).click();
  await expect(dialog).toBeHidden();

  await expect(dashboardEditor).toBeEmpty();
  await expect(dashboard.getByLabel("Date type")).toHaveCount(0);
  await expect(dashboard).not.toContainText("Draft saved on this device.");
  expect(await storedDraft(page, workspace.owner)).toBeNull();
});

test("a draft photo is shared by both composers and queued once", async ({
  page,
  workspace,
}) => {
  test.setTimeout(120_000);
  const { dashboard, dialog, dialogEditor, trigger } =
    await openDashboard(page);
  // Keep the capture on this device so no photo is uploaded.
  await setMemoTrailReachable(page, false);

  await addPhoto(dashboard, "shared-photo.png");
  await expect(photoButton(dashboard, "shared-photo.png")).toBeVisible();
  await trigger.click();
  await expect(dialogEditor).toBeFocused();
  await expect(photoButton(dialog, "shared-photo.png")).toBeVisible();
  await addPhoto(dialog, "second-photo.png");
  await dialog
    .getByRole("button", { name: "Remove selected shared-photo.png" })
    .click();
  await expect(photoButton(dialog, "shared-photo.png")).toHaveCount(0);
  await dialog.getByRole("button", { name: "Close quick capture" }).click();
  await expect(dialog).toBeHidden();
  await expect.soft(photoButton(dashboard, "shared-photo.png")).toHaveCount(0);
  await expect.soft(photoButton(dashboard, "second-photo.png")).toBeVisible();

  await trigger.click();
  await dialogEditor.fill("A photo worth keeping");
  await dialog
    .getByRole("button", { name: "Save to Library", exact: true })
    .click();
  await expect(dialogEditor).toBeEmpty();
  await expect(dialog.getByLabel("Draft photos")).toHaveCount(0);
  await dialog.getByRole("button", { name: "Close quick capture" }).click();
  await expect(dialog).toBeHidden();

  await expect.soft(dashboard.getByLabel("Draft photos")).toHaveCount(0);
  await dashboard
    .getByRole("button", { name: "Save to Library", exact: true })
    .click();
  const queue = await queuedCaptures(page, workspace.owner);
  expect(queue).toHaveLength(1);
  expect(queue[0]).toMatchObject({
    body: "A photo worth keeping",
    attachments: [{ name: "second-photo.png" }],
  });
  // Only the queued photo stays on this device; the removed one is gone.
  expect(await storedPhotoNames(page)).toEqual(["second-photo.png"]);
});

test("another tab follows the draft and its save", async ({
  context,
  page,
  workspace,
}) => {
  test.setTimeout(120_000);
  const first = await openDashboard(page);
  const otherPage = await context.newPage();
  const other = await openDashboard(otherPage);
  await setMemoTrailReachable(page, false);
  await setMemoTrailReachable(otherPage, false);

  await first.dashboardEditor.fill("Written in the first tab");
  await expect(other.dashboardEditor).toHaveText("Written in the first tab");
  await addPhoto(first.dashboard, "tab-photo.png");
  await expect(photoButton(other.dashboard, "tab-photo.png")).toBeVisible();
  await addPhoto(other.dashboard, "other-tab-photo.png");
  await expect(
    photoButton(first.dashboard, "other-tab-photo.png"),
  ).toBeVisible();
  await photoButton(first.dashboard, "other-tab-photo.png").click();
  await expect(photoButton(other.dashboard, "other-tab-photo.png")).toHaveCount(
    0,
  );
  await expect(photoButton(other.dashboard, "tab-photo.png")).toBeVisible();

  await first.dashboard
    .getByRole("button", { name: "Save to Library", exact: true })
    .click();
  await expect(first.dashboardEditor).toBeEmpty();
  await expect(other.dashboardEditor).toBeEmpty();
  await expect(other.dashboard.getByLabel("Draft photos")).toHaveCount(0);
  await other.dashboard
    .getByRole("button", { name: "Save to Library", exact: true })
    .click();
  await expect(other.dashboard).toContainText(
    "Write a title, a note, or add a photo before saving.",
  );
  const queue = await queuedCaptures(otherPage, workspace.owner);
  expect(queue).toHaveLength(1);
  expect(queue[0]).toMatchObject({
    body: "Written in the first tab",
    attachments: [{ name: "tab-photo.png" }],
  });
  expect(await storedPhotoNames(otherPage)).toEqual(["tab-photo.png"]);
  await otherPage.close();
});

test("voice capture follows the draft into Quick Capture and stops when it closes", async ({
  page,
  workspace,
}) => {
  test.setTimeout(120_000);
  await page.addInitScript(() => {
    type Listener = ((event?: unknown) => void) | null;
    // A scripted recognizer: the test speaks through `window.speakToCapture`.
    class ScriptedRecognition {
      continuous = false;
      interimResults = false;
      lang = "";
      onend: Listener = null;
      onerror: Listener = null;
      onresult: Listener = null;
      private phrases: string[] = [];
      start() {
        const voice = window as unknown as Record<string, unknown>;
        voice.speakToCapture = (phrase: string) => {
          this.phrases.push(phrase);
          this.onresult?.({
            results: this.phrases.map((transcript) => [{ transcript }]),
          });
        };
        voice.voiceSessions = Number(voice.voiceSessions ?? 0) + 1;
      }
      stop() {
        setTimeout(() => this.onend?.(), 0);
      }
      abort() {
        const voice = window as unknown as Record<string, unknown>;
        voice.abortedVoiceSessions =
          Number(voice.abortedVoiceSessions ?? 0) + 1;
      }
    }
    Object.assign(window, {
      SpeechRecognition: ScriptedRecognition,
      webkitSpeechRecognition: ScriptedRecognition,
    });
  });
  const { dashboard, dashboardEditor, dialog, dialogEditor, trigger } =
    await openDashboard(page);
  const speak = (phrase: string) =>
    page.evaluate(
      (words) =>
        (
          window as unknown as { speakToCapture: (words: string) => void }
        ).speakToCapture(words),
      phrase,
    );

  await dashboardEditor.fill("Before speaking.");
  await dashboard
    .getByRole("button", { name: "Start voice capture", exact: true })
    .click();
  await expect(
    dashboard.getByRole("status").filter({ hasText: "Listening" }),
  ).toBeVisible();
  await speak("first words ");
  await expect(dashboardEditor).toContainText("first words");

  await trigger.click();
  await expect(dialog).toBeVisible();
  await expect(dialogEditor).toContainText("first words");
  await expect(dialogEditor).toHaveAttribute("contenteditable", "false");
  await expect(
    dialog.getByRole("button", { name: "Stop voice capture", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await expect(dialog).toContainText(
    "Listening… Tap Stop when done. Audio is not saved.",
  );
  await expect(
    dialog.getByRole("button", { name: "Save to Library", exact: true }),
  ).toBeDisabled();
  await speak("and more");
  await expect(dialogEditor).toContainText("first words and more");

  await dialog.getByRole("button", { name: "Close quick capture" }).click();
  await expect(dialog).toBeHidden();
  expect(
    await page.evaluate(
      () =>
        (window as unknown as { abortedVoiceSessions?: number })
          .abortedVoiceSessions,
    ),
  ).toBe(1);
  await expect(dashboard).toContainText("Transcription added to this draft.");
  await expect(
    dashboard.getByRole("button", { name: "Start voice capture", exact: true }),
  ).toBeEnabled();
  await expect(dashboardEditor).toHaveAttribute("contenteditable", "true");
  await expect(dashboardEditor).toContainText("Before speaking.");
  await expect(dashboardEditor).toContainText("first words and more");
  await expect
    .poll(() => storedDraft(page, workspace.owner))
    .toMatchObject({ body: "Before speaking.\nfirst words and more" });

  // Voice capture started in Quick Capture stops from there too.
  await trigger.click();
  await dialog
    .getByRole("button", { name: "Start voice capture", exact: true })
    .click();
  await speak("from the dialog");
  await dialog
    .getByRole("button", { name: "Stop voice capture", exact: true })
    .click();
  await expect(dialog).toContainText("Transcription added to this draft.");
  await expect(dialogEditor).toContainText("from the dialog");
  await dialog
    .getByRole("button", { name: "Save to Library", exact: true })
    .click();
  await expect(dialogEditor).toBeEmpty();
  await expect(dialog).not.toContainText("Transcription added");
  await dialog.getByRole("button", { name: "Close quick capture" }).click();
  await expect(dashboardEditor).toBeEmpty();
  await expectEntryCount(
    workspace.client,
    "Before speaking.\nfirst words and more\nfrom the dialog",
    1,
  );
  // The save finishes once the Dashboard shows the new Entry.
  await expect(
    page.getByRole("region", { name: "Recent Entries", exact: true }),
  ).toContainText("Before speaking.");
});

async function openDashboard(page: Page) {
  await page.goto("/");
  const dashboard = page
    .locator("main")
    .getByRole("form", { name: "Quick capture", exact: true });
  const dashboardEditor = dashboard.getByRole("textbox", {
    name: "Entry text",
    exact: true,
  });
  const dialog = page.getByRole("dialog", { name: "What’s on your mind?" });
  const dialogEditor = dialog.getByRole("textbox", {
    name: "Entry text",
    exact: true,
  });
  const trigger = page.getByRole("button", { name: "New entry", exact: true });
  await expect(dashboardEditor).toBeVisible();
  await expect(
    dashboard.getByRole("button", { name: "Add photos", exact: true }),
  ).toBeEnabled();
  await page.waitForLoadState("networkidle");
  return { dashboard, dashboardEditor, dialog, dialogEditor, trigger };
}

async function addPhoto(composer: Locator, name: string) {
  await composer.locator('input[type="file"]').setInputFiles({
    name,
    mimeType: "image/png",
    buffer: await sharp({
      create: { width: 32, height: 24, channels: 3, background: "#426e83" },
    })
      .png()
      .toBuffer(),
  });
  await expect(photoButton(composer, name)).toBeVisible();
}

function photoButton(composer: Locator, name: string) {
  return composer.getByRole("button", {
    name: `Remove selected ${name}`,
    exact: true,
  });
}

function storedDraft(page: Page, owner: string) {
  return page.evaluate((ownerId) => {
    const stored = localStorage.getItem(`memotrail:inbox-draft:${ownerId}`);
    return stored ? JSON.parse(stored) : null;
  }, owner);
}

function queuedCaptures(page: Page, owner: string) {
  return page.evaluate((ownerId) => {
    const stored = localStorage.getItem(`memotrail:inbox-queue:${ownerId}`);
    return stored ? JSON.parse(stored) : [];
  }, owner);
}

/** Names of every photo this browser keeps for drafts and pending captures. */
function storedPhotoNames(page: Page) {
  return page.evaluate(
    () =>
      new Promise<string[]>((resolve, reject) => {
        const request = indexedDB.open("memotrail-capture");
        request.onerror = () => reject(request.error);
        request.onsuccess = () => {
          const database = request.result;
          const read = database
            .transaction("inbox-photo-drafts", "readonly")
            .objectStore("inbox-photo-drafts")
            .getAll();
          read.onerror = () => reject(read.error);
          read.onsuccess = () => {
            database.close();
            resolve(
              (read.result as { name: string }[])
                .map(({ name }) => name)
                .sort(),
            );
          };
        };
      }),
  );
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

async function entryCount(client: SupabaseClient, body: string) {
  return (await client.from("entries").select("id").eq("body", body)).data
    ?.length;
}

async function expectEntryCount(
  client: SupabaseClient,
  body: string,
  count: number,
) {
  await expect
    .poll(() => entryCount(client, body), { timeout: 20_000 })
    .toBe(count);
}
