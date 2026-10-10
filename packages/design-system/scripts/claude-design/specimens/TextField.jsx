import { Stack } from "./runtime.jsx";

const { TextField } = MemoTrail;

export const specimens = {
  "text-field-sizes": {
    title: "Small, medium, and large",
    render: () => (
      <Stack width="360px">
        <TextField label="Title" placeholder="Add a title" size="small" />
        <TextField label="Title" placeholder="Add a title" />
        <TextField label="Title" placeholder="Add a title" size="large" />
      </Stack>
    ),
  },
  "text-field-states": {
    title: "Filled and disabled",
    render: () => (
      <Stack width="360px">
        <TextField defaultValue="Learn to sail" label="Someday" />
        <TextField disabled defaultValue="Blue Civic" label="Vehicle name" />
      </Stack>
    ),
  },
};
