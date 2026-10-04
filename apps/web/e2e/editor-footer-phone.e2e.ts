import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test, type Locator, type Page } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

test("record editors keep Move to Trash, Cancel, and Save apart and reachable on a phone", async ({
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

    // A birth date keeps Timeline from opening its birth date prompt.
    expect(
      (
        await client
          .from("profiles")
          .update({ birth_date: "1990-01-01" })
          .eq("user_id", owner)
      ).error,
    ).toBeNull();
    // Each record is saved the way its editor saves it.
    const { data: track } = await client
      .from("timeline_tracks")
      .select("id")
      .limit(1)
      .single();
    const saves = await Promise.all([
      client.rpc("save_home_entry_with_occurrence", {
        p_address: null,
        p_body: "",
        p_city: null,
        p_country: null,
        p_date_precision: "day",
        p_entry_id: null,
        p_expected_revision: null,
        p_latitude: null,
        p_longitude: null,
        p_move_in_reason: null,
        p_move_out_reason: null,
        p_occurred_end: null,
        p_occurred_label: null,
        p_occurred_start: "2021-06-01T12:00:00+00:00",
        p_occurred_timezone: "UTC",
        p_place_id: null,
        p_place_name: null,
        p_place_notes: null,
        p_region: null,
        p_tag_names: [],
        p_title: "Maple Street flat",
      }),
      client.rpc("save_vehicle_entry", {
        p_body: "",
        p_color: "Blue",
        p_date_precision: "day",
        p_entry_id: null,
        p_expected_revision: null,
        p_make: "Memo",
        p_model: "Trail",
        p_model_year: 2019,
        p_occurred_end: null,
        p_occurred_label: null,
        p_occurred_start: "2019-09-15T12:00:00+00:00",
        p_occurred_timezone: "UTC",
        p_tag_names: [],
        p_title: "Blue hatchback",
      }),
      client.rpc("save_goal_entry", {
        p_body: "",
        p_entry_id: null,
        p_expected_revision: null,
        p_status: "active",
        p_tag_names: [],
        p_target_date: null,
        p_title: "Hike the coast trail",
      }),
      client.rpc("save_first_time_with_occurrence", {
        p_body: "",
        p_date_precision: "day",
        p_entry_id: null,
        p_expected_revision: null,
        p_occurred_end: null,
        p_occurred_label: null,
        p_occurred_start: "2024-03-02T12:00:00+00:00",
        p_occurred_timezone: "UTC",
        p_tag_names: [],
        p_title: "First sourdough loaf",
      }),
      client.rpc("save_timeline_entry_with_organization", {
        p_body: "",
        p_date_precision: "range",
        p_entry_id: null,
        p_expected_revision: null,
        p_occurred_end: "2017-07-15T12:00:00+00:00",
        p_occurred_label: null,
        p_occurred_start: "2017-07-08T12:00:00+00:00",
        p_occurred_timezone: "UTC",
        p_tag_names: [],
        p_timeline_kind: "stage",
        p_title: "First trip to Japan",
        p_track_id: track!.id,
      }),
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
      for (const [path, edit] of [
        [`/homes/${idFor("Maple Street flat")}`, "Edit Home"],
        [`/vehicles/${idFor("Blue hatchback")}`, "Edit Vehicle"],
        [`/goals/${idFor("Hike the coast trail")}`, "Edit Want to Do"],
        [`/first-times/${idFor("First sourdough loaf")}`, "Edit First Time"],
      ]) {
        await page.goto(path);
        await openEditor(
          page,
          page.getByRole("button", { name: edit, exact: true }),
        );
        await expectFooterApartAndReachable(page, `${edit} at ${width}`);
      }

      await page.goto("/timeline");
      await openEditor(
        page,
        page.getByRole("button", { name: /First trip to Japan/ }),
      );
      const dialog = page.getByRole("dialog");
      await expectFooterApartAndReachable(page, `Edit moment at ${width}`);
      // The footer lines up with the form above it, like every other editor.
      const title = await dialog
        .getByRole("textbox", { name: "Title" })
        .boundingBox();
      const save = await dialog
        .getByRole("button", { name: "Save changes", exact: true })
        .boundingBox();
      expect(
        Math.abs(title!.x + title!.width - (save!.x + save!.width)),
      ).toBeLessThan(1);
      if (width === 320)
        await page.screenshot({
          caret: "initial",
          path: "/private/tmp/memotrail-editor-footer-phone.png",
        });
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
 * Move to Trash, Cancel, and Save never overlap, and once the page or dialog
 * scrolls to its end each one is the element a tap at its center reaches.
 */
async function expectFooterApartAndReachable(page: Page, editor: string) {
  const save = page.getByRole("button", { name: "Save changes", exact: true });
  await expect(save).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Move to Trash", exact: true }),
  ).toBeVisible();
  await page.evaluate(() => {
    for (const element of [
      document.scrollingElement,
      ...document.querySelectorAll("*"),
    ])
      if (element && element.scrollHeight > element.clientHeight + 1)
        element.scrollTop = element.scrollHeight;
  });
  await expect
    .poll(
      () =>
        page.evaluate(() => {
          const buttons = [...document.querySelectorAll("button")].filter(
            (button) =>
              ["Move to Trash", "Cancel", "Save changes"].includes(
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
    .toEqual({ buttons: 3, overlapping: false, unreachable: [], wide: false });
}
