import { randomUUID } from "node:crypto";
import { type Locator, type Page } from "@playwright/test";
import { expect, test } from "./helpers/workspace-test";

test("Timeline adds without asking for a birth date and starts from the earliest item", async ({
  page,
  workspace: { client, owner },
}) => {
  test.setTimeout(90_000);
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto("/timeline");
  const prompt = page.getByRole("dialog", {
    name: "When did your story begin?",
  });
  const chooser = page.getByRole("dialog", { name: "What are you adding?" });

  // Add to Timeline goes straight to the chooser for an account without a birth date.
  // The shared Dialog mounts only on the client, so its visibility implies hydration.
  await page.getByRole("button", { name: "Add to Timeline" }).click();
  await expect(chooser).toBeVisible();
  await expect(prompt).toHaveCount(0);
  await chooser.getByRole("button", { name: "Close Timeline chooser" }).click();
  await expect(chooser).toHaveCount(0);

  // The empty Timeline offers the same chooser, so it never asks for a birth date either.
  await page
    .getByRole("button", {
      name: "Add a Chapter or a First Time to start your Timeline.",
    })
    .click();
  await expect(chooser).toBeVisible();
  await expect(prompt).toHaveCount(0);
  await chooser.getByRole("button", { name: "Close Timeline chooser" }).click();
  await expect(chooser).toHaveCount(0);

  // An empty Timeline shows this year and the next, with an axis that fills the card.
  const year = new Date().getUTCFullYear();
  const axis = page.getByTestId("timeline-axis").locator("span");
  await expect(axis.first()).toHaveText(String(year));
  await expect(axis.last()).toHaveText(String(year + 1));
  await expectBandsFillTimeline(page, 0);

  // Without a birth date, Timeline starts from the earliest dated item.
  const firstTimeId = randomUUID();
  expect(
    (
      await client.from("entries").insert({
        id: firstTimeId,
        owner_id: owner,
        title: "Moved into the studio",
        item_kind: "entry",
        item_subtype: "entry",
        is_first_time: true,
        occurred_start: `${year - 3}-06-01T12:00:00Z`,
        occurred_timezone: "UTC",
        date_precision: "day",
      })
    ).error,
  ).toBeNull();
  await page.reload();
  const summary = page.getByLabel("Timeline summary");
  await expect(summary).toContainText("1 First Time");
  await expect(summary).toContainText(new RegExp(`${year - 3} to \\d{4}`));
  await expect(axis.first()).toHaveText(String(year - 2));
  await expect(
    page
      .getByRole("region", { name: "Timeline by year" })
      .getByRole("link", { name: /Moved into the studio/ }),
  ).toBeVisible();
  await expectBandsFillTimeline(page, 1);
  await expect(prompt).toHaveCount(0);

  // Set birth date stays the way to begin Timeline at birth.
  await summary.getByRole("button", { name: "Set birth date" }).click();
  await expect(prompt).toBeVisible();
  const birthDateInput = prompt.getByLabel("Birth date", { exact: true });
  await expect(birthDateInput).toHaveValue("");
  await expect(birthDateInput).toHaveAttribute("readonly", "");
  await page.setViewportSize({ width: 390, height: 844 });
  await page.emulateMedia({ colorScheme: "dark" });
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBe(true);
  await page.screenshot({
    caret: "initial",
    path: test.info().outputPath("memotrail-timeline-birth-prompt-mobile.png"),
  });
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.emulateMedia({ colorScheme: "light" });
  await chooseBirthDate(page, birthDateInput, "1994-04-18");
  await prompt
    .getByRole("button", { name: "Save birth date", exact: true })
    .click();
  await expect(prompt).not.toBeVisible();
  await expect(axis.first()).toHaveText("1994");
  await expect(
    summary.getByRole("button", { name: "Set birth date" }),
  ).toHaveCount(0);
  await page.screenshot({
    caret: "initial",
    path: test.info().outputPath("memotrail-timeline-from-birth.png"),
  });
  await expect
    .poll(
      async () =>
        (
          await client
            .from("profiles")
            .select("birth_date")
            .eq("user_id", owner)
            .single()
        ).data?.birth_date,
    )
    .toBe("1994-04-18");

  await page.goto("/settings");
  const setting = page.getByRole("textbox", {
    name: "Birth date",
    exact: true,
  });
  await expect(setting).toHaveValue("1994-04-18");
  await expect(setting).not.toHaveAttribute("readonly", "");
  await setting.fill("1995abc05/19");
  await expect(setting).toHaveValue("1995-05-19");
  // A complete date saves on its own, with no button.
  await expect(
    page.locator("[data-setting-row]").filter({ has: setting }),
  ).toContainText("Saved");
  await expect(
    page.getByRole("button", { name: "Save birth date" }),
  ).toHaveCount(0);

  await page.goto("/timeline");
  await expect(axis.first()).toHaveText("1995");
  await expect(prompt).toHaveCount(0);
});

// The year axis and every band reach the right edge of the Timeline card.
async function expectBandsFillTimeline(page: Page, bands: number) {
  await expect
    .poll(() =>
      page.getByTestId("timeline-viewport").evaluate((viewport) => {
        const edge = viewport.getBoundingClientRect().right;
        const rows = viewport.querySelectorAll(
          '[data-testid="timeline-axis"], [data-testid="timeline-band"]',
        );
        return Array.from(rows).map((row) =>
          Math.max(0, Math.round(edge - row.getBoundingClientRect().right)),
        );
      }),
    )
    .toEqual(Array.from({ length: bands + 1 }, () => 0));
}

async function chooseBirthDate(page: Page, input: Locator, value: string) {
  const [yearText, monthText, dayText] = value.split("-");
  const year = Number(yearText);
  const month = Number(monthText);
  const day = Number(dayText);
  const monthName = new Intl.DateTimeFormat("en-US", {
    month: "long",
    timeZone: "UTC",
  }).format(new Date(Date.UTC(year, month - 1, 1)));

  await input.click();
  const yearView = page.getByRole("button", {
    name: "year view",
    exact: true,
  });
  await expect(yearView).toBeVisible();

  for (let attempt = 0; attempt < 20; attempt += 1) {
    const range = (await yearView.textContent())?.match(
      /(\d{4})\s*-\s*(\d{4})/,
    );
    if (!range) throw new Error("Date picker did not show a year range.");

    const rangeStart = Number(range[1]);
    const rangeEnd = Number(range[2]);
    if (year < rangeStart) {
      await page
        .getByRole("button", { name: "Previous period", exact: true })
        .click();
      continue;
    }
    if (year > rangeEnd) {
      await page
        .getByRole("button", { name: "Next period", exact: true })
        .click();
      continue;
    }
    break;
  }

  await page.getByRole("button", { name: yearText, exact: true }).click();
  await page
    .getByRole("button", { name: `${monthName} ${year}`, exact: true })
    .click();
  await page
    .getByRole("gridcell", {
      name: new RegExp(`${monthName} ${day}, ${year}`),
    })
    .click();
  await expect(input).toHaveValue(value);
}
