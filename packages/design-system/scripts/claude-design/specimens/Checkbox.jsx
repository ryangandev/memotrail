import { Stack } from "./runtime.jsx";

const { Checkbox } = MemoTrail;

export const specimens = {
  "checkbox-default": {
    title: "With an explanation",
    render: () => (
      <Stack width="420px">
        <Checkbox
          defaultChecked
          description="It appears on Timeline as a Moment or a Period."
          label="Add to Timeline"
        />
        <Checkbox label="First Time" />
      </Stack>
    ),
  },
  "checkbox-states": {
    title: "Small, and disabled",
    render: () => (
      <Stack width="420px">
        <Checkbox defaultChecked label="Show archived" size="small" />
        <Checkbox disabled label="Show archived" size="small" />
        <Checkbox defaultChecked disabled label="Present" />
      </Stack>
    ),
  },
};
