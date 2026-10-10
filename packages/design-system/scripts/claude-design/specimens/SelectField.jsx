import { Stack } from "./runtime.jsx";

const { SelectField } = MemoTrail;

const options = (
  <>
    <option value="system">System</option>
    <option value="light">Light</option>
    <option value="dark">Dark</option>
  </>
);

export const specimens = {
  "select-field-default": {
    title: "Default and small",
    render: () => (
      <Stack width="320px">
        <SelectField defaultValue="system" label="Appearance">
          {options}
        </SelectField>
        <SelectField defaultValue="light" label="Appearance" size="small">
          {options}
        </SelectField>
      </Stack>
    ),
  },
  "select-field-disabled": {
    title: "Disabled",
    render: () => (
      <Stack width="320px">
        <SelectField defaultValue="dark" disabled label="Appearance">
          {options}
        </SelectField>
      </Stack>
    ),
  },
};
