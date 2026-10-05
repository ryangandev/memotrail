import { randomUUID } from "node:crypto";
import { test, expect } from "./helpers/workspace-test";

const original = "Run the zebrafinch marathon";
// Server actions and the Goal page may compile on first use in development.
const firstCompile = { timeout: 30_000 };
const edited = "Run a half marathon";

// The bold note Web Capture stores for writing formatted in the composer.
function boldNote(text: string) {
  return {
    document: {
      content: [
        {
          content: [{ marks: [{ type: "bold" }], text, type: "text" }],
          type: "paragraph",
        },
      ],
      type: "doc",
    },
    text,
    version: 1,
  };
}

test("Editing a formatted Goal's writing removes its outdated formatted copy", async ({
  page,
  workspace: { owner, client },
}) => {
  // Several pages and server actions may compile for the first time in this scenario.
  test.setTimeout(120_000);
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  const itemID = randomUUID();
  expect(
    (
      await client.from("entries").insert({
        id: itemID,
        owner_id: owner,
        title: "Marathon plan",
        body: original,
        item_kind: "entry",
        item_subtype: "entry",
        metadata: { body_rich: boldNote(original) },
      })
    ).error,
  ).toBeNull();

  await page.goto(`/items/${itemID}`);
  await expect(
    page.getByRole("main").locator("strong", { hasText: original }),
  ).toBeVisible();
  const createForm = page.getByRole("form", { name: "Add to Want to Do" });
  // The Item page is server rendered, so a click before hydration opens nothing.
  await expect(async () => {
    if (!(await createForm.isVisible())) {
      await page
        .getByRole("button", { name: "Add to Want to Do", exact: true })
        .click();
    }
    await expect(createForm).toBeVisible({ timeout: 2_000 });
  }).toPass(firstCompile);
  await createForm.getByLabel("What do you want to do?").fill("Marathon goal");
  await createForm
    .getByRole("button", { name: "Add to Want to Do", exact: true })
    .click();
  await expect(page).toHaveURL(/\/goals\/[0-9a-f-]+$/, firstCompile);
  const goalID = new URL(page.url()).pathname.split("/").pop()!;
  const main = page.getByRole("main");
  const editButton = main.getByRole("button", { name: "Edit Want to Do" });
  const library = async (query: string) => {
    await page.goto(`/library?q=${encodeURIComponent(query)}`);
    return page.getByRole("region", { name: "Results", exact: true });
  };

  // A save that keeps the writing keeps the formatting the Goal copied.
  await editButton.click();
  await main.getByRole("textbox", { name: "Title" }).fill("Marathon training");
  await main.getByRole("button", { name: "Save changes", exact: true }).click();
  await expect(editButton).toBeVisible(firstCompile);
  let results = await library("zebrafinch");
  const goalResult = results
    .locator("article")
    .filter({ has: page.getByRole("link", { name: "Marathon training" }) });
  await expect(
    goalResult.locator("strong", { hasText: original }),
  ).toBeVisible();

  // Changing the writing in the plaintext editor drops the formatted copy.
  await page.goto(`/goals/${goalID}`);
  await editButton.click();
  await main.getByRole("textbox", { name: "Notes" }).fill(edited);
  await main.getByRole("button", { name: "Save changes", exact: true }).click();
  await expect(editButton).toBeVisible(firstCompile);
  await expect(main).toContainText(edited);
  await expect(main).not.toContainText("zebrafinch");

  results = await library("zebrafinch");
  await expect(
    results.getByRole("link", { name: "Marathon plan", exact: true }),
  ).toBeVisible();
  await expect(
    results.getByRole("link", { name: "Marathon training", exact: true }),
  ).toHaveCount(0);
  await expect(results).not.toContainText(edited);

  results = await library("half marathon");
  await expect(
    results.getByRole("link", { name: "Marathon training", exact: true }),
  ).toBeVisible();
  await expect(results.locator("strong")).toHaveCount(0);

  const goal = await client
    .from("entries")
    .select("body,metadata")
    .eq("id", goalID)
    .single();
  expect(goal.error).toBeNull();
  expect(goal.data).toEqual({ body: edited, metadata: {} });
  expect(errors).toEqual([]);
});
