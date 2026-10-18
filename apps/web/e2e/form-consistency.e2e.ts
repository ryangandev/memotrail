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
    await page
      .getByRole("button", { name: "Add to Someday", exact: true })
      .click();
    const goalDialog = page.getByRole("dialog", {
      name: "What do you want to do?",
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
    expect(goalPhotoStyle.pickerHeight).toBe("36px");
    await goalPhotos.screenshot({
      animations: "disabled",
      caret: "initial",
      path: test.info().outputPath("memotrail-goal-photo-field.png"),
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
    const tagLegend = goalDialog.getByText("Tags", { exact: true });
    const tagInput = goalDialog.getByRole("combobox", {
      name: "Tags",
      exact: true,
    });
    await tagInput.scrollIntoViewIfNeeded();
    const [legendBox, tagFieldBox] = await Promise.all([
      tagLegend.boundingBox(),
      tagInput.locator("..").boundingBox(),
    ]);
    expect(
      Math.round(
        (tagFieldBox?.y ?? 0) -
          ((legendBox?.y ?? 0) + (legendBox?.height ?? 0)),
      ),
    ).toBeGreaterThanOrEqual(8);
    await goalDialog
      .getByRole("button", { name: "Close Someday editor", exact: true })
      .click();
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
