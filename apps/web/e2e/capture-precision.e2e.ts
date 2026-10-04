import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect, type Page } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import sharp from "sharp";
import {
  fillOccurrenceEnd,
  fillOccurrenceStart,
  occurrenceStartField,
  setDateDescription,
} from "./helpers/occurrence";
import { parseInboxDraft } from "../src/lib/data/inbox-draft";

test("Quick capture retains uncertain dates in drafts and offline replay", async ({
  page,
  context,
}) => {
  const env = JSON.parse(
    execFileSync("supabase", ["status", "-o", "json"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }),
  );
  expect(env.API_URL).toBe("http://127.0.0.1:54321");
  const admin = createClient(env.API_URL, env.SERVICE_ROLE_KEY);
  const email = `capture-precision-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  const owner = created.data.user!.id;
  try {
    const cookies: { name: string; value: string }[] = [];
    const client = createServerClient(env.API_URL, env.ANON_KEY, {
      cookies: {
        getAll: () => cookies,
        setAll: (values) => {
          cookies.push(
            ...values.map((v) => ({ name: v.name, value: v.value })),
          );
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
      cookies.map((c) => ({
        ...c,
        domain: "127.0.0.1",
        path: "/",
        sameSite: "Lax",
        httpOnly: false,
      })),
    );
    await page.goto("/");
    const capture = page.getByRole("form", {
      name: "Quick capture",
      exact: true,
    });
    // The editor mounts only after hydration; a photo chosen before it would be ignored.
    await expect(
      capture.getByRole("textbox", { name: "Entry text", exact: true }),
    ).toBeVisible({ timeout: 30_000 });
    await capture.locator('input[type="file"]').setInputFiles({
      name: "quick-preview.png",
      mimeType: "image/png",
      buffer: await sharp({
        create: { width: 320, height: 240, channels: 3, background: "#426e83" },
      })
        .png()
        .toBuffer(),
    });
    const removePhoto = capture.getByRole("button", {
      name: "Remove selected quick-preview.png",
    });
    const removeIconOffset = await removePhoto.evaluate((button) => {
      const icon = button.querySelector("svg")?.getBoundingClientRect();
      const bounds = button.getBoundingClientRect();
      return icon
        ? Math.hypot(
            icon.x + icon.width / 2 - (bounds.x + bounds.width / 2),
            icon.y + icon.height / 2 - (bounds.y + bounds.height / 2),
          )
        : Infinity;
    });
    expect(removeIconOffset).toBeLessThan(0.5);
    await capture
      .getByRole("button", { name: "Preview selected quick-preview.png" })
      .click();
    const photoPreview = page.getByRole("dialog", {
      name: "quick-preview.png",
    });
    await expect(photoPreview).toBeVisible();
    await photoPreview
      .getByRole("button", { name: "Close", exact: true })
      .click();
    await removePhoto.click();
    await expect(
      capture.getByRole("button", {
        name: "Preview selected quick-preview.png",
      }),
    ).toHaveCount(0);
    await capture.getByRole("button", { name: "Date", exact: true }).click();
    await expect(capture.getByLabel("Date type")).toBeVisible({
      timeout: 5000,
    });
    await expect(
      capture.getByRole("textbox", { name: "Entry title", exact: true }),
    ).toHaveCount(0);
    await capture
      .getByRole("textbox", { name: "Entry text", exact: true })
      .fill("Recovered partial draft");
    await expect
      .poll(() =>
        page.evaluate((ownerId) => {
          const stored = localStorage.getItem(
            `memotrail:inbox-draft:${ownerId}`,
          );
          return stored ? JSON.parse(stored) : null;
        }, owner),
      )
      .toMatchObject({
        body: "Recovered partial draft",
        bodyRich: { text: "Recovered partial draft", version: 1 },
      });
    await capture.getByLabel("Date type").selectOption("year");
    await occurrenceStartField(capture).fill("20");
    const storedDraft = await page.evaluate(
      (ownerId) => localStorage.getItem(`memotrail:inbox-draft:${ownerId}`),
      owner,
    );
    expect(parseInboxDraft(storedDraft)).toMatchObject({
      body: "Recovered partial draft",
    });
    await page.reload();
    await expect(occurrenceStartField(capture)).toHaveValue("20");
    await capture
      .getByRole("button", { name: "Save to Library", exact: true })
      .click();
    await expect(capture).toContainText("Choose a valid calendar date");
    expect((await client.from("entries").select("id")).data).toHaveLength(0);

    const cases = [
      { precision: "exact", start: "2017-07-08T12:34", label: "", end: "" },
      { precision: "day", start: "2017-07-08", label: "", end: "" },
      { precision: "month", start: "2017-07", label: "", end: "" },
      { precision: "year", start: "2017", label: "", end: "" },
      {
        precision: "approximate",
        start: "",
        label: "Summer before college",
        end: "",
      },
      { precision: "age", start: "", label: "At age 17", end: "" },
      { precision: "range", start: "2017-07-01", label: "", end: "2017-08-12" },
      { precision: "unknown", start: "", label: "", end: "" },
    ];
    for (const [index, item] of cases.entries()) {
      if (index > 0)
        await capture
          .getByRole("button", { name: "Date", exact: true })
          .click();
      await capture
        .getByRole("textbox", { name: "Entry text", exact: true })
        .fill(`Capture ${item.precision}`);
      await capture.getByLabel("Date type").selectOption(item.precision);
      await capture
        .getByRole("combobox", { name: "Time zone", exact: true })
        .selectOption("Asia/Kathmandu");
      if (item.start) await fillOccurrenceStart(capture, item.start);
      await setDateDescription(capture, item.label);
      if (item.end) await fillOccurrenceEnd(capture, item.end);
      if (item.precision === "age") {
        await page.setViewportSize({ width: 390, height: 844 });
        await page.emulateMedia({ colorScheme: "dark" });
        await page.screenshot({
          caret: "initial",
          path: "/private/tmp/memotrail-capture-precision-mobile.png",
        });
        await page.waitForLoadState("networkidle");
        await context.setOffline(true);
      }
      if (index === 0)
        await page.screenshot({
          caret: "initial",
          path: "/private/tmp/memotrail-capture-precision-desktop.png",
        });
      let delayedSync = false;
      if (index === 0) {
        await watchPendingSyncSurfaces(page);
        await page.route("**/*", async (route) => {
          if (
            !delayedSync &&
            route.request().method() === "POST" &&
            route.request().headers()["next-action"]
          ) {
            delayedSync = true;
            await new Promise((resolve) => setTimeout(resolve, 750));
          }
          await route.continue();
        });
      }
      await capture
        .getByRole("button", { name: "Save to Library", exact: true })
        .click();
      if (item.precision === "age") {
        await expect(
          page.getByRole("heading", { name: "Pending sync", exact: true }),
        ).toBeVisible();
        // The closed Quick Capture mirrors the same shared queue.
        await expect(
          page.locator("main article").filter({
            hasText: "Capture age",
          }),
        ).toContainText("At age 17");
        const pending = await page.evaluate(
          (owner) =>
            JSON.parse(localStorage.getItem(`memotrail:inbox-queue:${owner}`)!),
          owner,
        );
        expect(pending[0]).toMatchObject({
          version: 3,
          datePrecision: "age",
          occurredAt: null,
          occurredEnd: null,
          occurredLabel: "At age 17",
        });
        await context.setOffline(false);
        // Let the online listener finish its retry/refresh before exercising
        // reload recovery, rather than aborting its in-flight RSC stream.
        await page.waitForLoadState("networkidle");
        await page.reload();
      }
      await expect
        .poll(
          async () =>
            (
              await client
                .from("entries")
                .select("id")
                .eq("body", `Capture ${item.precision}`)
            ).data?.length,
        )
        .toBe(1);
      if (index === 0) {
        expect(delayedSync).toBe(true);
        expect(
          await page.evaluate(() =>
            sessionStorage.getItem("pending-sync-seen"),
          ),
        ).toBe("no");
        await page.unroute("**/*");
      }
      const saved = (
        await client
          .from("entries")
          .select("*")
          .eq("body", `Capture ${item.precision}`)
          .single()
      ).data!;
      expect(saved).toMatchObject({
        body: `Capture ${item.precision}`,
        date_precision: item.precision,
        occurred_timezone: "Asia/Kathmandu",
        occurred_label: item.label || null,
        title: null,
      });
      if (!item.start) expect(saved.occurred_start).toBeNull();
      else {
        const expected =
          item.precision === "exact"
            ? "2017-07-08T06:49:00"
            : `${item.precision === "year" ? "2017-01-01" : item.precision === "month" ? "2017-07-01" : item.start}T06:15:00`;
        expect(saved.occurred_start).toBe(`${expected}+00:00`);
      }
      expect(saved.occurred_end).toBe(
        item.end ? "2017-08-12T06:15:00+00:00" : null,
      );
      await expect(
        capture.getByRole("button", { name: "Save to Library", exact: true }),
      ).toBeEnabled();
    }

    await capture.getByRole("button", { name: "Date", exact: true }).click();
    await capture.getByLabel("Date type").selectOption("unknown");
    await capture
      .getByRole("button", { name: "Use capture time", exact: true })
      .click();
    await expect(capture.getByLabel("Date type")).toHaveCount(0);
    await capture
      .getByRole("textbox", { name: "Entry text", exact: true })
      .fill("Default capture time");
    const beforeDefault = Date.now();
    await capture
      .getByRole("button", { name: "Save to Library", exact: true })
      .click();
    await expect
      .poll(
        async () =>
          (
            await client
              .from("entries")
              .select("id")
              .eq("body", "Default capture time")
          ).data?.length,
      )
      .toBe(1);
    const defaultEntry = (
      await client
        .from("entries")
        .select("*")
        .eq("body", "Default capture time")
        .single()
    ).data!;
    expect(defaultEntry.title).toBeNull();
    expect(defaultEntry.date_precision).toBe("exact");
    expect(Date.parse(defaultEntry.occurred_start)).toBeGreaterThanOrEqual(
      beforeDefault,
    );
    expect(Date.parse(defaultEntry.occurred_start)).toBeLessThanOrEqual(
      Date.now(),
    );
    expect(defaultEntry.occurred_end).toBeNull();
    expect(defaultEntry.occurred_label).toBeNull();

    await page.getByRole("button", { name: "New entry" }).click();
    const newCapture = page.getByRole("dialog", {
      name: "What’s on your mind?",
    });
    await newCapture
      .getByRole("textbox", { name: "Entry text" })
      .fill("Capture from New");
    await watchPendingSyncSurfaces(page);
    let delayedModalSync = false;
    await page.route("**/*", async (route) => {
      if (
        !delayedModalSync &&
        route.request().method() === "POST" &&
        route.request().headers()["next-action"]
      ) {
        delayedModalSync = true;
        await new Promise((resolve) => setTimeout(resolve, 750));
      }
      await route.continue();
    });
    await newCapture
      .getByRole("button", { name: "Save to Library", exact: true })
      .click();
    await expect(
      newCapture.getByRole("button", { name: "Saving…", exact: true }),
    ).toBeDisabled();
    await expect
      .poll(
        async () =>
          (
            await client
              .from("entries")
              .select("id")
              .eq("body", "Capture from New")
          ).data?.length,
      )
      .toBe(1);
    expect(delayedModalSync).toBe(true);
    expect(
      await page.evaluate(() => sessionStorage.getItem("pending-sync-seen")),
    ).toBe("no");
    await page.unroute("**/*");
    await expect(
      newCapture.getByRole("button", { name: "Save to Library", exact: true }),
    ).toBeEnabled();
    await newCapture
      .getByRole("button", { name: "Close quick capture" })
      .click();

    // Old pending payloads retain their UUID/date and are not duplicated on replay.
    const legacyId = randomUUID();
    await page.evaluate(
      ({ owner, legacyId }) => {
        localStorage.setItem(
          `memotrail:inbox-queue:${owner}`,
          JSON.stringify([
            {
              version: 1,
              id: legacyId,
              title: "Legacy capture",
              body: "Older client",
              occurredAt: "2017-07-08T12:34:56.123456Z",
              occurredTimezone: "UTC",
              queuedAt: "2026-09-01T00:00:00Z",
            },
          ]),
        );
      },
      { owner, legacyId },
    );
    await page.reload();
    await expect
      .poll(
        async () =>
          (await client.from("entries").select("id").eq("id", legacyId)).data
            ?.length,
      )
      .toBe(1);
    expect(
      (
        await client
          .from("entries")
          .select("date_precision,occurred_start")
          .eq("id", legacyId)
          .single()
      ).data,
    ).toMatchObject({
      date_precision: "exact",
      occurred_start: "2017-07-08T12:34:56.123456+00:00",
    });
  } finally {
    await context.setOffline(false);
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});

// Records whether any pending list or the header pending indicator appears,
// because an online save's first attempt must not surface either.
async function watchPendingSyncSurfaces(page: Page) {
  await page.evaluate(() => {
    sessionStorage.setItem("pending-sync-seen", "no");
    new MutationObserver(() => {
      const listed = [...document.querySelectorAll("h2")].some(
        (heading) => heading.textContent === "Pending sync",
      );
      const indicated = [
        ...document.querySelectorAll("main > header button"),
      ].some((button) => /^\d+ pending$/.test(button.textContent ?? ""));
      if (listed || indicated) {
        sessionStorage.setItem("pending-sync-seen", "yes");
      }
    }).observe(document.body, {
      characterData: true,
      childList: true,
      subtree: true,
    });
  });
}
