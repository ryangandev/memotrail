import { test, expect } from "./helpers/workspace-test";

test("floating capture opens, restores drafts, saves, and adapts to the viewport", async ({
  page,
  workspace,
}) => {
  test.setTimeout(120_000);
  const profile = await workspace.client
    .from("profiles")
    .update({ display_name: "Preview" })
    .eq("user_id", workspace.owner);
  expect(profile.error).toBeNull();
  await page.setViewportSize({ width: 1440, height: 960 });
  await page.goto("/");
  await expect(
    page.getByRole("textbox", { name: "Entry text", exact: true }),
  ).toBeVisible();
  const trigger = page.getByRole("button", { name: "New entry", exact: true });
  const search = page.getByRole("button", {
    name: "Search your trail",
    exact: true,
  });
  const dialog = page.getByRole("dialog", {
    name: "What’s on your mind?",
    exact: true,
  });
  const editor = dialog.getByRole("textbox", {
    name: "Entry text",
    exact: true,
  });
  await expect(
    page.locator("main > header").getByRole("button", { name: "New entry" }),
  ).toHaveCount(0);
  await expect(trigger).toHaveAttribute("aria-expanded", "false");
  await expect(
    page
      .locator("main > header")
      .getByRole("button", { name: "Search your trail" }),
  ).toHaveCount(0);
  const triggerBox = (await trigger.boundingBox())!;
  const searchBox = (await search.boundingBox())!;
  expect(triggerBox.y + triggerBox.height).toBeCloseTo(936, 0);
  expect(searchBox.x + searchBox.width).toBeLessThan(triggerBox.x);
  expect(searchBox.y).toBeCloseTo(triggerBox.y, 0);
  expect((searchBox.x + triggerBox.x + triggerBox.width) / 2).toBeCloseTo(
    (1440 + 224) / 2,
    0,
  );
  await expect(search).toHaveCSS("backdrop-filter", /blur/);
  await search.focus();
  await page.keyboard.press("Tab");
  await expect(trigger).toBeFocused();
  await page.screenshot({
    animations: "disabled",
    clip: {
      x: searchBox.x - 16,
      y: triggerBox.y - 12,
      width: triggerBox.x + triggerBox.width - searchBox.x + 32,
      height: triggerBox.height + 24,
    },
    path: "/private/tmp/memotrail-action-dock-desktop.png",
  });
  await page.screenshot({
    animations: "disabled",
    path: "/private/tmp/memotrail-capture-dock-desktop.png",
  });

  await trigger.click();
  await expect(editor).toBeFocused();
  await editor.fill("A quiet moment worth keeping.");
  await editor.press("Escape");
  await expect(dialog).not.toBeVisible();
  await expect(trigger).toBeFocused();
  await page.keyboard.press("Meta+j");
  await expect(editor).toHaveText("A quiet moment worth keeping.");
  await expect(editor).toBeFocused();
  await page.keyboard.press("Shift+Tab");
  await expect(
    dialog.getByRole("button", { name: "Close quick capture" }),
  ).toBeFocused();
  await page.keyboard.press("Shift+Tab");
  expect(
    await dialog.evaluate((element) =>
      element.contains(document.activeElement),
    ),
  ).toBe(true);
  await editor.focus();
  await page.screenshot({
    animations: "disabled",
    path: "/private/tmp/memotrail-capture-dock-expanded.png",
  });
  await dialog
    .getByRole("button", { name: "Save to Inbox", exact: true })
    .click();
  await expect(
    page.locator("[data-sonner-toast]").filter({ hasText: "Saved to Inbox." }),
  ).toBeVisible();
  await expect
    .poll(async () => {
      const result = await workspace.client
        .from("entries")
        .select("body,inbox_status")
        .eq("owner_id", workspace.owner);
      expect(result.error).toBeNull();
      return result.data;
    })
    .toEqual([
      expect.objectContaining({
        body: "A quiet moment worth keeping.",
        inbox_status: "unreviewed",
      }),
    ]);
  await dialog.getByRole("button", { name: "Close quick capture" }).click();

  await page
    .getByRole("navigation", { name: "Primary navigation", exact: true })
    .getByRole("link", { name: "Library", exact: true })
    .click();
  await expect(page).toHaveURL(/\/library$/);
  await trigger.focus();
  await page.keyboard.press("Control+j");
  await expect(editor).toHaveText("");
  await editor.fill("A draft to come back to.");
  await editor.press("Escape");
  await page.reload();
  await trigger.click();
  await expect(editor).toHaveText("A draft to come back to.");
  // Outside-click dismissal keeps the same draft and returns keyboard focus.
  await page.mouse.click(20, 100);
  await expect(dialog).not.toBeVisible();
  await expect(trigger).toBeFocused();
  await page.emulateMedia({ colorScheme: "dark" });
  await trigger.click();
  await expect(editor).toBeFocused();
  await page.screenshot({
    animations: "disabled",
    path: "/private/tmp/memotrail-capture-dock-dark.png",
  });
  await editor.press("Escape");

  await page.emulateMedia({ colorScheme: "light", reducedMotion: "reduce" });
  for (const width of [390, 320]) {
    await page.setViewportSize({ width, height: 844 });
    const navBox = (await page
      .getByRole("navigation", { name: "Mobile navigation" })
      .boundingBox())!;
    const dockBox = (await trigger.boundingBox())!;
    const mobileSearchBox = (await search.boundingBox())!;
    expect(dockBox.y + dockBox.height).toBeLessThan(navBox.y);
    expect(mobileSearchBox.x).toBeGreaterThanOrEqual(12);
    expect(mobileSearchBox.x + mobileSearchBox.width).toBeLessThan(dockBox.x);
    expect(mobileSearchBox.y).toBeCloseTo(dockBox.y, 0);
    expect(dockBox.x + dockBox.width).toBeLessThanOrEqual(width - 12);
    await page.screenshot({
      animations: "disabled",
      path: `/private/tmp/memotrail-capture-dock-mobile-${width}.png`,
    });
    await search.click();
    const palette = page.getByRole("dialog", { name: "Search MemoTrail" });
    await expect(palette.getByRole("searchbox")).toBeFocused();
    await page.keyboard.press("Escape");
    await expect(palette).not.toBeVisible();
    await trigger.click();
    await expect(editor).toBeFocused();
    await expect(dialog).toHaveCSS("animation-name", "none");
    await expect(
      dialog.getByRole("button", { name: "Save to Inbox", exact: true }),
    ).toBeInViewport();
    const box = (await dialog.boundingBox())!;
    expect(box.x).toBeGreaterThanOrEqual(12);
    expect(box.x + box.width).toBeLessThanOrEqual(width - 12);
    expect(box.y).toBeGreaterThanOrEqual(12);
    expect(box.y + box.height).toBeLessThanOrEqual(844 - 12);
    await page.screenshot({
      animations: "disabled",
      path: `/private/tmp/memotrail-capture-dock-mobile-expanded-${width}.png`,
    });
    await page.setViewportSize({ width, height: 430 });
    await dialog
      .getByRole("button", { name: "Save to Inbox", exact: true })
      .scrollIntoViewIfNeeded();
    await expect(
      dialog.getByRole("button", { name: "Save to Inbox", exact: true }),
    ).toBeInViewport();
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth),
    ).toBe(width);
    await dialog.getByRole("button", { name: "Close quick capture" }).click();
  }
});
