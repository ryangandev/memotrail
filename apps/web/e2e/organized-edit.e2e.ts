import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { test, expect } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
test("Organized Entries stay editable without returning to Inbox", async ({
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
  const email = `organized-edit-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
  });
  const owner = created.data.user!.id,
    id = randomUUID(),
    collectionId = randomUUID();
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
    expect(
      (
        await client.from("entries").insert({
          id,
          owner_id: owner,
          title: "Finished organizing",
          body: "Original words",
          item_kind: "writing",
          item_subtype: "note",
          inbox_status: "organized",
          date_precision: "exact",
          metadata: {
            body_rich: {
              document: {
                content: [
                  {
                    content: [
                      {
                        marks: [{ type: "bold" }],
                        text: "Original words",
                        type: "text",
                      },
                    ],
                    type: "paragraph",
                  },
                ],
                type: "doc",
              },
              text: "Original words",
              version: 1,
            },
          },
          occurred_start: "2017-07-08T12:34:56.123456Z",
          occurred_timezone: "Asia/Kathmandu",
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("collections").insert({
          id: collectionId,
          owner_id: owner,
          name: "Rich notes",
        })
      ).error,
    ).toBeNull();
    expect(
      (
        await client.from("entry_collections").insert({
          collection_id: collectionId,
          entry_id: id,
          owner_id: owner,
        })
      ).error,
    ).toBeNull();
    await page.goto(`/history?entry=${id}`);
    const currentVersion = page.getByRole("region", {
      name: "Current version",
      exact: true,
    });
    await expect(
      currentVersion.locator("strong").filter({ hasText: /^Original words$/ }),
    ).toHaveText("Original words");
    await page
      .getByRole("button", { name: "Edit Entry", exact: true })
      .click({ timeout: 5000 });
    const dialog = page.getByRole("dialog");
    await expect(
      dialog.getByRole("button", { name: "Done", exact: true }),
    ).toHaveCount(0);
    await expect(
      dialog.getByRole("complementary", { name: "AI suggestions" }),
    ).toHaveCount(0);
    const noteEditor = dialog.getByRole("textbox", {
      name: "Note",
      exact: true,
    });
    await expect(noteEditor.locator("strong")).toHaveText("Original words");
    await page.screenshot({
      path: "/private/tmp/memotrail-organized-editor-desktop.png",
    });
    await noteEditor.press("Meta+k");
    const linkEditor = dialog.getByRole("group", {
      name: "Link editor",
      exact: true,
    });
    await expect(linkEditor).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(linkEditor).not.toBeVisible();
    await expect(dialog).toBeVisible();
    await noteEditor.fill("Updated after organizing");
    await dialog.getByRole("button", { name: "Cancel", exact: true }).click();
    expect(
      (await client.from("entries").select("body").eq("id", id).single()).data!
        .body,
    ).toBe("Original words");
    await page.getByRole("button", { name: "Edit Entry", exact: true }).click();
    await page.setViewportSize({ width: 390, height: 844 });
    await page.emulateMedia({ colorScheme: "dark" });
    await expect(noteEditor.locator("strong")).toHaveText("Original words");
    await page.screenshot({
      path: "/private/tmp/memotrail-organized-editor-mobile.png",
    });
    await noteEditor.fill("Updated after organizing");
    await noteEditor.press("Meta+a");
    await dialog.getByRole("button", { name: "Italic", exact: true }).click();
    await expect(noteEditor.locator("em")).toHaveText(
      "Updated after organizing",
    );
    await dialog
      .getByRole("button", { name: "Save changes", exact: true })
      .click();
    await expect(dialog).not.toBeVisible();
    const saved = (
      await client.from("entries").select("*").eq("id", id).single()
    ).data!;
    expect(saved).toMatchObject({
      body: "Updated after organizing",
      inbox_status: "organized",
      date_precision: "exact",
      metadata: {
        body_rich: {
          text: "Updated after organizing",
          version: 1,
        },
      },
      occurred_start: "2017-07-08T12:34:56.123456+00:00",
      revision: 2,
    });
    await expect(currentVersion.locator("em")).toHaveText(
      "Updated after organizing",
    );
    expect(
      (
        await client
          .from("entry_versions")
          .select("snapshot")
          .eq("entry_id", id)
          .eq("version", 1)
          .single()
      ).data!.snapshot.body,
    ).toBe("Original words");
    await page.goto(`/collections/${collectionId}`);
    await expect(
      page
        .locator("[data-entry-rich-text] em")
        .filter({ hasText: /^Updated after organizing$/ }),
    ).toHaveText("Updated after organizing");
    await page.goto("/search?q=Updated%20after%20organizing");
    await expect(
      page
        .locator("[data-entry-rich-text] em")
        .filter({ hasText: /^Updated after organizing$/ }),
    ).toHaveText("Updated after organizing");
    await page.goto("/inbox");
    await expect(
      page.getByRole("heading", { name: "Finished organizing", exact: true }),
    ).toHaveCount(0);
  } finally {
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
