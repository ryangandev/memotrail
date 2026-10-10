import { Stack } from "./runtime.jsx";

const { TextField } = MemoTrail;

export const specimens = {
  "text-field-sizes": {
    title: "Small, medium, and large",
    render: () => (
      <Stack width="360px">
        <TextField defaultValue="Alex" label="Nickname" size="small" />
        <TextField defaultValue="Alex Morgan" label="Preferred name" />
        <TextField
          defaultValue="Alexandra Morgan"
          label="Full name"
          size="large"
        />
      </Stack>
    ),
  },
  "text-field-states": {
    title: "Empty, required, disabled, and invalid",
    render: () => (
      <Stack width="360px">
        <TextField label="Empty text field" placeholder="Add a name" />
        <TextField
          defaultValue="A moment worth keeping"
          label="Title"
          required
        />
        <TextField
          disabled
          label="Disabled text field"
          placeholder="Unavailable"
        />
        <TextField error="Add a city before saving." label="City" />
      </Stack>
    ),
  },
};
