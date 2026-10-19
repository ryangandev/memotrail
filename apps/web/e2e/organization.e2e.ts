import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";
import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";
import {
  fillOccurrenceStart,
  setOccurrencePrecision,
} from "./helpers/occurrence";

test("Tags are first-class and organize generic Timeline moments", async ({
  context,
  page,
}) => {
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
  const email = `organization-${randomUUID()}@memotrail.local`;
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
    password: randomUUID(),
  });
  if (!created.data.user)
    throw new Error("Could not create local test account.");
  const owner = created.data.user.id;

  try {
    const cookies: { name: string; value: string }[] = [];
    const client = createServerClient(env.API_URL, env.ANON_KEY, {
      cookies: {
        getAll: () => cookies,
        setAll: (values) => {
          for (const value of values) {
            cookies.push({ name: value.name, value: value.value });
          }
        },
      },
    });
    const link = await admin.auth.admin.generateLink({
      type: "magiclink",
      email,
    });
    if (!link.data.properties) {
      throw new Error("Could not establish local fixture session.");
    }
    expect(
      (
        await client.auth.verifyOtp({
          token_hash: link.data.properties.hashed_token,
          type: "magiclink",
        })
      ).error,
    ).toBeNull();
    await context.addCookies(
      cookies.map((cookie) => ({
        ...cookie,
        domain: "127.0.0.1",
        httpOnly: false,
        path: "/",
        sameSite: "Lax" as const,
      })),
    );
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    page.on("console", (message) => {
      if (message.type() === "error") errors.push(message.text());
    });

    await page.setViewportSize({ width: 1440, height: 900 });
    for (const path of ["/collections", `/collections/${randomUUID()}`]) {
      await page.goto(path);
      await expect(page).toHaveURL(/\/tags$/);
    }
    await page.goto("/library");
    await page
      .getByRole("navigation", { name: "Primary navigation" })
      .getByRole("link", { name: "Tags", exact: true })
      .click();
    await expect(page).toHaveURL(/\/tags$/);
    await expect(
      page.getByRole("navigation", { name: "Archive organization" }),
    ).toHaveCount(0);
    for (const name of ["travel", "journeys", "unused"]) {
      await page.getByRole("button", { name: "New Tag" }).click();
      const tagDialog = page.getByRole("dialog", { name: "Create a Tag" });
      await tagDialog
        .getByRole("textbox", { name: "Name", exact: true })
        .fill(name);
      await tagDialog.getByRole("button", { name: "Create Tag" }).click();
      await expect(tagDialog).not.toBeVisible();
      await expect(
        page.getByRole("button", {
          name: `Manage tag ${name}, used by 0 Entries`,
        }),
      ).toBeVisible();
    }

    const tagSearch = page.getByRole("search", { name: "Find tags" });
    const tagList = page.getByRole("region", { name: "Tags" });
    await expect(tagSearch).toBeVisible();
    await expect(tagList).toBeVisible();
    const searchSurface = await tagSearch.evaluate((element) => {
      const style = getComputedStyle(element);
      return {
        background: style.backgroundColor,
        borderWidth: Number.parseFloat(style.borderWidth),
      };
    });
    expect(searchSurface.background).toBe("rgba(0, 0, 0, 0)");
    expect(searchSurface.borderWidth).toBe(0);
    const tagSurface = await tagList.evaluate((element) => {
      const style = getComputedStyle(element);
      return {
        background: style.backgroundColor,
        borderWidth: Number.parseFloat(style.borderWidth),
        width: element.getBoundingClientRect().width,
      };
    });
    expect(tagSurface.background).toBe("rgba(0, 0, 0, 0)");
    expect(tagSurface.borderWidth).toBe(0);
    await expect(
      page.getByRole("heading", { level: 1, name: "Tags", exact: true }),
    ).toBeVisible();
    await expect(page.getByText("3 tags", { exact: true })).toBeVisible();
    await expect(
      tagList.getByText("Select a tag to browse the Entries using it"),
    ).toHaveCount(0);
    // Tags are ledger rows: one button each, stacked and ruled, never chips.
    const tagRows = tagList.getByRole("listitem");
    await expect(tagRows).toHaveCount(3);
    await expect(tagRows.first().getByRole("button")).toHaveAccessibleName(
      /Manage tag .+, used by 0 Entries/,
    );
    await expect(tagRows.first().getByRole("button")).toHaveCount(1);
    await expect(tagRows.first()).toContainText("0 Entries");
    const rowBoxes = await tagRows.evaluateAll((elements) =>
      elements.map((element) => {
        const box = element.getBoundingClientRect();
        return {
          borderBottom: Number.parseFloat(
            getComputedStyle(element).borderBottomWidth,
          ),
          height: box.height,
          width: box.width,
          y: box.y,
        };
      }),
    );
    expect(rowBoxes[1].y).toBeGreaterThan(
      rowBoxes[0].y + rowBoxes[0].height - 1,
    );
    expect(rowBoxes.every((box) => box.height < 64)).toBe(true);
    expect(rowBoxes.every((box) => box.borderBottom === 1)).toBe(true);
    expect(rowBoxes.every((box) => box.width === tagSurface.width)).toBe(true);
    const searchControlHeights = await Promise.all(
      [
        tagSearch.locator("[data-search-control]"),
        tagSearch.getByRole("button"),
      ].map((control) =>
        control.evaluate((element) => element.getBoundingClientRect().height),
      ),
    );
    expect(
      Math.abs(searchControlHeights[0] - searchControlHeights[1]),
    ).toBeLessThan(1);
    await page.screenshot({
      animations: "disabled",
      caret: "initial",
      fullPage: true,
      path: test.info().outputPath("memotrail-tags-consistent.png"),
    });

    await page.goto("/timeline");
    await page.getByRole("button", { name: "Add to Timeline" }).click();
    await page
      .getByRole("dialog", { name: "What are you adding?" })
      .getByRole("button", { name: "Add First Time", exact: true })
      .click();
    const momentDialog = page.getByRole("dialog", {
      name: "Add a First Time",
    });
    await momentDialog
      .getByLabel("Title", { exact: true })
      .fill("Moved to Seattle");
    await setOccurrencePrecision(momentDialog, "day");
    await fillOccurrenceStart(momentDialog, "2025-03-14");
    const momentTags = momentDialog.getByRole("combobox", {
      name: "Tags",
      exact: true,
    });
    await momentTags.fill("travel");
    await momentTags.press("Enter");
    await momentDialog
      .getByRole("button", { name: "Add", exact: true })
      .click();
    await expect(momentDialog).not.toBeVisible();

    const entry = await client
      .from("entries")
      .select("id")
      .eq("owner_id", owner)
      .eq("title", "Moved to Seattle")
      .single();
    expect(entry.error).toBeNull();
    expect(
      (
        await client
          .from("entry_tags")
          .select("tag_id", { count: "exact", head: true })
          .eq("entry_id", entry.data!.id)
      ).count,
    ).toBe(1);

    await page.goto("/tags");
    const travelRow = tagList
      .getByRole("listitem")
      .filter({ hasText: "travel" });
    await expect(travelRow.getByText("1 Entry", { exact: true })).toBeVisible();
    await travelRow
      .getByRole("button", { name: "Manage tag travel, used by 1 Entry" })
      .click();
    const travelDialog = page.getByRole("dialog", { name: "travel" });
    expect(
      await travelDialog.evaluate((element) => element.closest("li") === null),
    ).toBe(true);
    expect(await travelDialog.locator("..").boundingBox()).toMatchObject({
      height: page.viewportSize()?.height,
      width: page.viewportSize()?.width,
      x: 0,
      y: 0,
    });
    await travelDialog
      .getByRole("button", { name: "Close tag editor", exact: true })
      .click();
    await expect(travelDialog).not.toBeVisible();
    await travelRow
      .getByRole("button", { name: "Manage tag travel, used by 1 Entry" })
      .click();
    await expect(
      travelDialog.getByText("Used by 1 Entry", { exact: true }),
    ).toBeVisible();
    await expect(
      travelDialog.getByRole("link", { name: "Moved to Seattle" }),
    ).toBeVisible();
    await expect(
      travelDialog.getByRole("link", {
        name: "View all Entries for this tag",
      }),
    ).toBeVisible();
    // Cancel discards an unsaved rename, so the next open shows the saved name.
    const travelName = travelDialog.getByRole("textbox", {
      exact: true,
      name: "Name",
    });
    await travelName.fill("travel, unsaved");
    await travelDialog.getByRole("button", { name: "Cancel" }).click();
    await expect(travelDialog).not.toBeVisible();
    await travelRow
      .getByRole("button", { name: "Manage tag travel, used by 1 Entry" })
      .click();
    await expect(travelName).toHaveValue("travel");
    await page.screenshot({
      animations: "disabled",
      caret: "initial",
      path: test.info().outputPath("memotrail-tag-editor.png"),
    });
    await page.emulateMedia({ colorScheme: "dark" });
    await page.screenshot({
      animations: "disabled",
      caret: "initial",
      path: test.info().outputPath("memotrail-tag-editor-dark.png"),
    });
    await page.emulateMedia({ colorScheme: "light" });
    await travelDialog
      .getByLabel("Destination tag")
      .selectOption({ label: "#journeys (0)" });
    await expect(
      travelDialog.getByRole("button", { name: "Merge tag" }),
    ).toHaveCSS("height", "36px");
    await travelDialog.getByRole("button", { name: "Merge tag" }).click();
    await page
      .getByRole("dialog", { name: /Merge “travel” into “journeys”\?/ })
      .getByRole("button", { name: "Merge tags", exact: true })
      .click();
    await expect(travelDialog).not.toBeVisible();
    await expect(
      page.getByRole("button", {
        name: "Manage tag travel, used by 1 Entry",
      }),
    ).toHaveCount(0);
    const journeysRow = tagList
      .getByRole("listitem")
      .filter({ hasText: "journeys" });
    await expect(
      journeysRow.getByText("1 Entry", { exact: true }),
    ).toBeVisible();
    await journeysRow
      .getByRole("button", { name: "Manage tag journeys, used by 1 Entry" })
      .click();
    const journeysDialog = page.getByRole("dialog", { name: "journeys" });
    await journeysDialog
      .getByRole("link", { name: "View all Entries for this tag" })
      .click();
    await expect(page).toHaveURL(/\/library\?tag=journeys$/);
    await expect(
      page.getByRole("combobox", { name: "Tag", exact: true }),
    ).toHaveValue("journeys");
    await expect(
      page.getByRole("heading", { name: "Moved to Seattle", exact: true }),
    ).toBeVisible();
    await page.goto("/tags");

    const unusedRow = tagList
      .getByRole("listitem")
      .filter({ hasText: "unused" });
    await expect(
      unusedRow.getByText("0 Entries", { exact: true }),
    ).toBeVisible();
    await unusedRow
      .getByRole("button", { name: "Manage tag unused, used by 0 Entries" })
      .click();
    const unusedDialog = page.getByRole("dialog", { name: "unused" });
    await unusedDialog
      .getByRole("button", { name: "Delete unused tag" })
      .click();
    await page
      .getByRole("dialog", { name: "Delete the unused tag “unused”?" })
      .getByRole("button", { name: "Delete tag", exact: true })
      .click();
    await expect(unusedDialog).not.toBeVisible();
    await expect(
      page.getByRole("button", {
        name: "Manage tag unused, used by 0 Entries",
      }),
    ).toHaveCount(0);

    await page.goto("/settings/organization");
    await expect(page).toHaveURL(/\/tags$/);
    await page.screenshot({
      animations: "disabled",
      caret: "initial",
      fullPage: true,
      path: test.info().outputPath("memotrail-tags-desktop.png"),
    });
    await page.setViewportSize({ height: 844, width: 390 });
    await page.screenshot({
      animations: "disabled",
      caret: "initial",
      fullPage: true,
      path: test.info().outputPath("memotrail-tags-mobile.png"),
    });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    expect(errors).toEqual([]);
  } finally {
    expect((await admin.auth.admin.deleteUser(owner)).error).toBeNull();
  }
});
