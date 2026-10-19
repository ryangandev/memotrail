import { randomUUID } from "node:crypto";
import { expect, test } from "./helpers/workspace-test";

test("Someday and Map addresses lead to Library or the Entry they became", async ({
  page,
  workspace: { client, owner },
}) => {
  const entryId = randomUUID();
  expect(
    (
      await client.from("entries").insert({
        id: entryId,
        owner_id: owner,
        title: "Visit Kyoto in autumn",
        body: "See the maple leaves turn.",
        item_kind: "entry",
        item_subtype: "entry",
        date_precision: "unknown",
        occurred_timezone: "UTC",
      })
    ).error,
  ).toBeNull();

  for (const path of ["/goals", `/goals/${entryId}/edit`, "/map", "/map/x"]) {
    await page.goto(path);
    await expect(page, path).toHaveURL(/\/library$/);
    await expect(
      page.getByRole("heading", { name: "Library", exact: true }),
    ).toBeVisible();
  }

  // An old item address opens the Item page while the Entry exists.
  await page.goto(`/goals/${entryId}`);
  await expect(page).toHaveURL(new RegExp(`/items/${entryId}$`));
  await expect(
    page.getByRole("heading", { name: "Visit Kyoto in autumn" }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Add to Someday" }),
  ).toHaveCount(0);

  // An item that is gone has nothing to open, so its address opens Library.
  await page.goto(`/goals/${randomUUID()}`);
  await expect(page).toHaveURL(/\/library$/);

  // Neither destination is offered in navigation.
  const navigation = page.getByRole("navigation", {
    name: "Primary navigation",
  });
  await expect(navigation.getByRole("link", { name: "Library" })).toBeVisible();
  for (const name of ["Map", "Someday"]) {
    await expect(navigation.getByRole("link", { name })).toHaveCount(0);
  }
  await expect(
    page.getByRole("complementary").getByRole("link", { name: "Someday" }),
  ).toHaveCount(0);
});
