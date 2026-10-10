import { Stack } from "./runtime.jsx";

const { DatePickerField } = MemoTrail;

// DatePickerField follows the DateField spec, so its specimen ids start with date-field.
export const specimens = {
  "date-field-precision": {
    title: "Day, month, and year precision",
    render: () => (
      <Stack width="320px">
        <DatePickerField defaultValue="2026-09-17" label="Filled date" />
        <DatePickerField
          defaultValue="2026-09"
          granularity="month"
          label="Month precision"
        />
        <DatePickerField
          defaultValue="2026"
          granularity="year"
          label="Year precision"
        />
      </Stack>
    ),
  },
  "date-field-with-time": {
    title: "With a time of day",
    render: () => (
      <Stack width="320px">
        <DatePickerField
          defaultValue="2026-09-17T14:30"
          includeTime
          label="Exact date and time"
        />
      </Stack>
    ),
  },
  "date-field-sizes": {
    title: "Small, medium, and large",
    render: () => (
      <Stack width="320px">
        <DatePickerField defaultValue="2026-09-01" label="From" size="small" />
        <DatePickerField defaultValue="2026-09-17" label="Start date" />
        <DatePickerField
          defaultValue="1990-04-12"
          label="Birth date"
          size="large"
        />
      </Stack>
    ),
  },
  "date-field-states": {
    title: "Empty, required, disabled, and picker only",
    render: () => (
      <Stack width="320px">
        <DatePickerField label="Empty date" />
        <DatePickerField label="Due date" required />
        <DatePickerField defaultValue="2026-09-17" disabled label="Disabled" />
        <DatePickerField editable={false} label="Picker only" />
      </Stack>
    ),
  },
};
