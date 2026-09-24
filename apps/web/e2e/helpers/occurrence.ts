import { expect, type Locator, type Page } from "@playwright/test";

type OccurrenceScope = Locator | Page;

const startDateName = /^(Occurred|Start date)$/;

export function occurrenceStartField(scope: OccurrenceScope) {
  return scope.getByRole("textbox", { name: startDateName });
}

export async function fillOccurrenceStart(
  scope: OccurrenceScope,
  value: string,
) {
  await fillDateField(occurrenceStartField(scope), scope, value);
}

export async function fillOccurrenceEnd(scope: OccurrenceScope, value: string) {
  const present = scope.getByRole("checkbox", {
    name: "Present",
    exact: true,
  });
  await expect(present).toBeVisible();
  if (await present.isChecked()) await present.uncheck();
  await fillDateField(
    scope.getByRole("textbox", { name: "End date", exact: true }),
    scope,
    value,
  );
}

export async function setDateDescription(
  scope: OccurrenceScope,
  value: string,
) {
  const toggle = scope.getByRole("checkbox", { name: "Add date description" });
  if (await toggle.count()) {
    if (!value) {
      if (await toggle.isChecked()) await toggle.uncheck();
      return;
    }
    if (!(await toggle.isChecked())) await toggle.check();
  }
  await scope.getByRole("textbox", { name: "Date description" }).fill(value);
}

async function fillDateField(
  dateField: Locator,
  scope: OccurrenceScope,
  value: string,
) {
  const [date, time] = value.split("T");
  await dateField.fill(date);
  if (!time) return;

  const label = await dateField.getAttribute("aria-label");
  if (!label)
    throw new Error("Occurrence date field needs an accessible label.");
  const title = `Choose ${label.toLowerCase()} time`;
  await scope.getByRole("button", { name: title, exact: true }).click();
  const picker = dateField.page().getByRole("dialog", {
    name: title,
    exact: true,
  });
  const [hour, minute] = time.split(":");
  await picker.getByRole("combobox", { name: "Hour" }).selectOption(hour);
  await picker.getByRole("combobox", { name: "Minute" }).selectOption(minute);
  await picker.getByRole("button", { name: "Done", exact: true }).click();
}
