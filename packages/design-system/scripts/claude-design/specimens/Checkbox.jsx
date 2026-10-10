import { Stack } from "./runtime.jsx";

const { Checkbox } = MemoTrail;

export const specimens = {
  "checkbox-sizes": {
    title: "Medium and small, unchecked and checked",
    render: () => (
      <Stack gap="var(--mt-space-3)" width="420px">
        <Checkbox label="Unchecked" />
        <Checkbox
          defaultChecked
          description="Shown on the Timeline"
          label="Checked"
        />
        <Checkbox label="Small unchecked" size="small" />
        <Checkbox
          defaultChecked
          description="Still going on"
          label="Small checked"
          size="small"
        />
      </Stack>
    ),
  },
  "checkbox-states": {
    title: "A long description, disabled, and disabled while checked",
    render: () => (
      <Stack gap="var(--mt-space-3)" width="420px">
        <Checkbox description="Controlled by this page" label="Remind me" />
        <Checkbox
          description="A longer explanation wraps below the label until it needs another line, and never runs past its container."
          label="With description"
        />
        <Checkbox disabled label="Disabled" />
        <Checkbox
          defaultChecked
          description="Cannot change"
          disabled
          label="Disabled checked"
        />
      </Stack>
    ),
  },
};
