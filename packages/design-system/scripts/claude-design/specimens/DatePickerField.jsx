import { Stack } from "./runtime.jsx";

const { DatePickerField } = MemoTrail;

export const specimens = {
  "date-picker-field-precision": {
    title: "Day, month, and year precision",
    render: () => (
      <Stack width="320px">
        <DatePickerField defaultValue="2026-09-18" label="Date" />
        <DatePickerField
          defaultValue="2026-09"
          granularity="month"
          label="Month"
        />
        <DatePickerField defaultValue="2018" granularity="year" label="Year" />
      </Stack>
    ),
  },
  "date-picker-field-with-time": {
    title: "With a time, small",
    render: () => (
      <Stack width="320px">
        <DatePickerField
          defaultValue="2026-09-18T08:30"
          includeTime
          label="Date and time"
          size="small"
        />
      </Stack>
    ),
  },
};
