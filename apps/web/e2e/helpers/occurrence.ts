import { expect, type Locator, type Page } from "@playwright/test";

type OccurrenceScope = Locator | Page;

const startDateName = /^(Occurred|Start date|Calendar anchor \(optional\))$/;

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

async function fillDateField(
  dateField: Locator,
  scope: OccurrenceScope,
  value: string,
) {
  const [date, time] = value.split("T");
  await dateField.fill(date);
  if (!time) return;

  const label = await dateField.getAttribute("aria-label");
  if (!label) throw new Error("Occurrence date field needs an accessible label.");
  await scope
    .getByRole("textbox", { name: `${label} time`, exact: true })
    .fill(time);
}
