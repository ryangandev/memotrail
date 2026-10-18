import { expect, test } from "./helpers/workspace-test";

test("An unknown page keeps the workspace and offers the way back", async ({
  page,
  workspace,
}) => {
  void workspace;
  const response = await page.goto("/no-such-page");

  expect(response?.status()).toBe(404);
  await expect(
    page.getByRole("heading", { name: "Page not found" }),
  ).toBeVisible();
  // The sidebar stays, so there is always somewhere to go next.
  await expect(
    page.getByRole("navigation", { name: "Primary navigation" }),
  ).toBeVisible();
  await page.screenshot({
    animations: "disabled",
    caret: "initial",
    path: test.info().outputPath("memotrail-not-found.png"),
  });

  await page
    .getByRole("main")
    .getByRole("link", { name: "Go to Home" })
    .click();
  await expect(page).toHaveURL(/\/$/);
});
