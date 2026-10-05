import { expect, type Locator, type Page } from "@playwright/test";

type OccurrenceScope = Locator | Page;

const startDateName = /^(Occurred|Start date|Roughly when)$/;

export type DatePrecision =
  | "exact"
  | "day"
  | "month"
  | "year"
  | "approximate"
  | "age"
  | "range"
  | "unknown";

const segmentNames: Record<DatePrecision, string> = {
  exact: "Day",
  day: "Day",
  range: "Day",
  unknown: "Day",
  month: "Month",
  year: "Year",
  approximate: "Not sure",
  age: "Not sure",
};

export function occurrenceField(scope: OccurrenceScope) {
  return scope.getByRole("group", { name: "Date", exact: true });
}

// Chooses a stored precision through the editor: a segment, then the Add time and
// Add end date toggles. An unknown date is a Day left empty, and an age is only kept.
export async function setOccurrencePrecision(
  scope: OccurrenceScope,
  precision: DatePrecision,
) {
  const field = occurrenceField(scope);
  await field
    .getByRole("button", { name: segmentNames[precision], exact: true })
    .click();
  if (segmentNames[precision] !== "Day") return;
  const time = field.getByRole("checkbox", { name: "Add time", exact: true });
  const end = field.getByRole("checkbox", {
    name: "Add end date",
    exact: true,
  });
  if (precision !== "range" && (await end.count()) && (await end.isChecked()))
    await end.uncheck();
  if (precision !== "exact" && (await time.count()) && (await time.isChecked()))
    await time.uncheck();
  if (precision === "exact") await time.check();
  if (precision === "range" && (await end.count())) await end.check();
  if (precision === "unknown") await occurrenceStartField(field).fill("");
}

export async function expectOccurrencePrecision(
  scope: OccurrenceScope,
  precision: DatePrecision,
) {
  const field = occurrenceField(scope);
  await expect(
    field.getByRole("button", { name: segmentNames[precision], exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  if (segmentNames[precision] !== "Day") return;
  const time = field.getByRole("checkbox", { name: "Add time", exact: true });
  const end = field.getByRole("checkbox", {
    name: "Add end date",
    exact: true,
  });
  if (precision === "range") {
    // Outside a Period a range is Add end date; in a Period every Day has an end.
    if (await end.count()) await expect(end).toBeChecked();
    return;
  }
  await expect(time).toBeChecked({ checked: precision === "exact" });
  if (await end.count()) await expect(end).not.toBeChecked();
  if (precision === "unknown")
    await expect(occurrenceStartField(field)).toHaveValue("");
}

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
  const toggle = scope.getByRole("checkbox", {
    name: "Add end date",
    exact: true,
  });
  if ((await toggle.count()) && !(await toggle.isChecked()))
    await toggle.check();
  const present = scope.getByRole("checkbox", {
    name: "Present",
    exact: true,
  });
  if ((await present.count()) && (await present.isChecked()))
    await present.uncheck();
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
