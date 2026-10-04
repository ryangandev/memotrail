import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test, type Locator } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";
import sharp from "sharp";

test("specialized forms share photo fields and required-label conventions", async ({
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
  const email = `form-consistency-${randomUUID()}@memotrail.local`;
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

    await page.goto("/goals");
    await page.getByRole("button", { name: "Add Goal", exact: true }).click();
    const goalDialog = page.getByRole("dialog", {
      name: "Keep an intention close",
      exact: true,
    });
    await expect(
      goalDialog.getByText("Title *", { exact: true }),
    ).toBeVisible();
    await expect(goalDialog.getByText(/Optional/i)).toHaveCount(0);
    const goalPhotos = goalDialog.locator('[data-entry-photo-field="true"]');
    await expect(goalPhotos).toBeVisible();
    const goalPhotoStyle = await photoFieldStyle(goalPhotos);
    expect(goalPhotoStyle.borderTopWidth).toBe("0px");
    expect(goalPhotoStyle.pickerHeight).toBe("42px");
    await goalPhotos.screenshot({
      animations: "disabled",
      caret: "initial",
      path: "/private/tmp/memotrail-goal-photo-field.png",
    });
    await goalPhotos.locator('input[type="file"]').setInputFiles({
      name: "goal-preview.png",
      mimeType: "image/png",
      buffer: await sharp({
        create: { width: 320, height: 240, channels: 3, background: "#426e83" },
      })
        .png()
        .toBuffer(),
    });
    await goalPhotos
      .getByRole("button", { name: "Preview selected goal-preview.png" })
      .click();
    const preview = page.getByRole("dialog", { name: "goal-preview.png" });
    await expect(preview).toBeVisible();
    await preview.getByRole("button", { name: "Close", exact: true }).click();
    await expect(preview).not.toBeVisible();
    await expect(goalDialog).toBeVisible();
    await goalPhotos
      .getByRole("button", { name: "Remove selected goal-preview.png" })
      .click();
    await expect(
      goalPhotos.getByRole("button", {
        name: "Preview selected goal-preview.png",
      }),
    ).toHaveCount(0);
    for (const [legendText, kind] of [["Tags", "tag"]] as const) {
      const legend = goalDialog.getByText(legendText, { exact: true });
      await goalDialog
        .getByRole("button", { name: `Add ${kind}`, exact: true })
        .click();
      const input = goalDialog.getByRole("combobox", {
        name: `Search or create a ${kind}`,
      });
      await input.scrollIntoViewIfNeeded();
      const fieldShell = input.locator("..");
      const [legendBox, inputBox] = await Promise.all([
        legend.boundingBox(),
        fieldShell.boundingBox(),
      ]);
      expect(
        Math.round(
          (inputBox?.y ?? 0) - ((legendBox?.y ?? 0) + (legendBox?.height ?? 0)),
        ),
      ).toBeGreaterThanOrEqual(8);
      await input.press("Escape");
    }
    await goalDialog
      .getByRole("button", { name: "Close Goal editor", exact: true })
      .click();

    await page.goto("/first-times");
    await page
      .getByRole("button", { name: "Add First Time", exact: true })
      .click();
    const firstTimeDialog = page.getByRole("dialog", {
      name: "Keep a beginning",
      exact: true,
    });
    const firstTimePhotos = firstTimeDialog.locator(
      '[data-entry-photo-field="true"]',
    );
    await expect(firstTimePhotos).toBeVisible();
    expect(await photoFieldStyle(firstTimePhotos)).toEqual(goalPhotoStyle);
    await firstTimeDialog
      .getByRole("button", { name: "Close First Time editor", exact: true })
      .click();

    await page.goto("/people");
    await page.getByRole("button", { name: "Add Person", exact: true }).click();
    const personDialog = page.getByRole("dialog", {
      name: "Keep someone in your story",
      exact: true,
    });
    await expect(
      personDialog.getByText("Name *", { exact: true }),
    ).toBeVisible();
    await expect(personDialog.getByText(/Optional/i)).toHaveCount(0);
    const close = personDialog.getByRole("button", {
      name: "Close Person editor",
      exact: true,
    });
    await expect(close.locator("svg")).toHaveCount(1);
    const personPanel = personDialog.locator(":scope > div");
    await expect
      .poll(() => personPanel.evaluate((element) => element.scrollLeft))
      .toBe(0);
    await page.screenshot({
      caret: "initial",
      path: "/private/tmp/memotrail-person-editor.png",
      animations: "disabled",
    });
    await close.click();
    await expect(personDialog).not.toBeVisible();
  } finally {
    await admin.auth.admin.deleteUser(owner);
  }
});

async function photoFieldStyle(field: Locator) {
  return field.evaluate((element: HTMLElement) => {
    const style = getComputedStyle(element);
    const picker = element.querySelector("label");
    return {
      borderTopWidth: style.borderTopWidth,
      pickerHeight: picker ? getComputedStyle(picker).height : "missing",
    };
  });
}
