import { Stack } from "./runtime.jsx";

const { SelectField } = MemoTrail;

export const specimens = {
  "select-field-sizes": {
    title: "Small, medium, and large",
    render: () => (
      <Stack width="320px">
        <SelectField defaultValue="newest" label="Sort by" size="small">
          <option value="newest">Newest first</option>
          <option value="oldest">Oldest first</option>
        </SelectField>
        <SelectField defaultValue="all" label="Show">
          <option value="all">All</option>
          <option value="entries">Entries</option>
          <option value="chapters">Chapters</option>
        </SelectField>
        <SelectField defaultValue="timeline" label="Default view" size="large">
          <option value="dashboard">Dashboard</option>
          <option value="timeline">Timeline</option>
          <option value="library">Library</option>
        </SelectField>
      </Stack>
    ),
  },
  "select-field-groups": {
    title: "Required, with titled groups",
    render: () => (
      <Stack width="320px">
        <SelectField defaultValue="all" label="Kind" required>
          <option value="all">All</option>
          <optgroup label="Entry kinds">
            <option value="entries">Entries</option>
            <option value="chapters">Chapters</option>
          </optgroup>
          <optgroup label="Marks">
            <option value="first-times">First Times</option>
            <option value="favorites">Favorites</option>
          </optgroup>
        </SelectField>
      </Stack>
    ),
  },
  "select-field-disabled": {
    title: "Disabled",
    render: () => (
      <Stack width="320px">
        <SelectField disabled label="Unavailable filter" size="small">
          <option>Unavailable</option>
        </SelectField>
      </Stack>
    ),
  },
};
