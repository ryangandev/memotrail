import { Stack } from "./runtime.jsx";

const { SegmentedControl } = MemoTrail;

const themes = [
  { label: "System", value: "system" },
  { label: "Light", value: "light" },
  { label: "Dark", value: "dark" },
];

const precisions = [
  { label: "Day", value: "day" },
  { label: "Month", value: "month" },
];

function Choice({ disabled, initial, label, options }) {
  const [value, setValue] = React.useState(initial);
  return (
    <SegmentedControl
      disabled={disabled}
      label={label}
      onChange={setValue}
      options={options}
      value={value}
    />
  );
}

export const specimens = {
  "segmented-control-states": {
    title: "Three options, two options, and disabled",
    render: () => (
      <Stack gap="var(--mt-space-4)" width="420px">
        <Choice initial="system" label="Theme" options={themes} />
        <Choice initial="day" label="Date precision" options={precisions} />
        <Choice disabled initial="light" label="Theme" options={themes} />
      </Stack>
    ),
  },
};
