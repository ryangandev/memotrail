import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test, type Locator, type Page } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

test("Entry editors keep Cancel and Save apart and reachable on a phone", async ({
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
  const email = `editor-footer-${randomUUID()}@memotrail.local`;
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

    // Each Entry is saved the way its editor saves it.
    const entry = (
      title: string,
      start: string,
      marks: { chapter: boolean; firstTime: boolean },
      precision = "day",
      end: string | null = null,
    ) =>
      client.rpc("save_entry", {
        p_body: "",
        p_body_rich: null,
        p_date_precision: precision,
        p_entry_id: randomUUID(),
        p_expected_revision: null,
        p_is_chapter: marks.chapter,
        p_is_first_time: marks.firstTime,
        p_occurred_end: end,
        p_occurred_label: null,
        p_occurred_start: start,
        p_occurred_timezone: "UTC",
        p_photo_location: null,
        p_primary_location: null,
        p_tag_names: [],
        p_title: title,
      });
    const saves = await Promise.all([
      entry("Maple Street flat", "2021-06-01T12:00:00+00:00", {
        chapter: true,
        firstTime: false,
      }),
      entry("Blue hatchback years", "2019-09-15T12:00:00+00:00", {
        chapter: true,
        firstTime: false,
      }),
      entry(
        "First trip to Japan",
        "2017-07-08T12:00:00+00:00",
        { chapter: false, firstTime: true },
        "range",
        "2017-07-15T12:00:00+00:00",
      ),
    ]);
    for (const saved of saves) expect(saved.error).toBeNull();
    const { data: records, error } = await client
      .from("entries")
      .select("id,title")
      .eq("owner_id", owner);
    expect(error).toBeNull();
    const idFor = (title: string) =>
      records!.find((record) => record.title === title)!.id;

    for (const width of [390, 320]) {
      await page.setViewportSize({ width, height: 844 });
      // A Chapter and a First Time are edited as Entries, in the same editor.
      for (const [title, edit] of [
        ["Maple Street flat", "Edit Chapter"],
        ["Blue hatchback years", "Edit Chapter"],
        ["First trip to Japan", "Edit Entry"],
      ]) {
        await page.goto(`/items/${idFor(title)}`);
        await openEditor(
          page,
          page.getByRole("button", { name: edit, exact: true }),
        );
        await expectFooterApartAndReachable(page, `${title} at ${width}`);
        const dialog = page.getByRole("dialog", { name: "Edit Entry" });
        // The footer lines up with the form above it, like every other editor.
        const titleBox = await dialog
          .getByRole("textbox", { name: "Title" })
          .boundingBox();
        const saveBox = await dialog
          .getByRole("button", { name: "Save changes", exact: true })
          .boundingBox();
        expect(
          Math.abs(
            titleBox!.x + titleBox!.width - (saveBox!.x + saveBox!.width),
          ),
        ).toBeLessThan(1);
        if (width === 320 && title === "First trip to Japan")
          await page.screenshot({
            caret: "initial",
            path: test.info().outputPath("memotrail-editor-footer-phone.png"),
          });
      }
    }
  } finally {
    await admin.auth.admin.deleteUser(owner);
  }
});

/** Opens an editor, retrying a click made before the page hydrated. */
async function openEditor(page: Page, opener: Locator) {
  const save = page.getByRole("button", { name: "Save changes", exact: true });
  await expect(async () => {
    if (!(await save.isVisible())) await opener.click();
    await expect(save).toBeVisible({ timeout: 2_000 });
  }).toPass({ timeout: 90_000 });
}

/**
 * Cancel and Save never overlap, and once the dialog scrolls to its end each one
 * is the element a tap at its center reaches.
 */
async function expectFooterApartAndReachable(page: Page, editor: string) {
  const save = page.getByRole("button", { name: "Save changes", exact: true });
  await expect(save).toBeVisible();
  await page.evaluate(() => {
    for (const element of [
      document.scrollingElement,
      ...document.querySelectorAll('[role="dialog"], [role="dialog"] *'),
    ])
      if (element && element.scrollHeight > element.clientHeight + 1)
        element.scrollTop = element.scrollHeight;
  });
  await expect
    .poll(
      () =>
        page.evaluate(() => {
          const dialog = document.querySelector('[role="dialog"]')!;
          const buttons = [...dialog.querySelectorAll("button")].filter(
            (button) =>
              ["Cancel", "Save changes"].includes(
                button.textContent?.trim() ?? "",
              ) && button.getBoundingClientRect().width > 0,
          );
          const boxes = buttons.map((button) => button.getBoundingClientRect());
          const overlapping = boxes.some((a, index) =>
            boxes
              .slice(index + 1)
              .some(
                (b) =>
                  a.left < b.right - 0.5 &&
                  b.left < a.right - 0.5 &&
                  a.top < b.bottom - 0.5 &&
                  b.top < a.bottom - 0.5,
              ),
          );
          const unreachable = buttons
            .filter((button, index) => {
              const box = boxes[index];
              const hit = document.elementFromPoint(
                box.left + box.width / 2,
                box.top + box.height / 2,
              );
              return !hit || !button.contains(hit);
            })
            .map((button) => button.textContent?.trim());
          return {
            buttons: buttons.length,
            overlapping,
            unreachable,
            wide: document.documentElement.scrollWidth > window.innerWidth,
          };
        }),
      { message: editor },
    )
    .toEqual({ buttons: 2, overlapping: false, unreachable: [], wide: false });
}
