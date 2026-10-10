import { Stack } from "./runtime.jsx";

const { Badge, SearchField } = MemoTrail;

export const specimens = {
  "search-field-default": {
    title: "Labeled search",
    render: () => (
      <Stack width="420px">
        <SearchField
          label="Search Library"
          placeholder="A phrase, date, or question about your life..."
        />
      </Stack>
    ),
  },
  "search-field-hidden-label": {
    title: "Hidden label, small and large, with a trailing element",
    render: () => (
      <Stack width="420px">
        <SearchField
          hideLabel
          label="Find a tag"
          placeholder="Find or create tag"
          size="small"
        />
        <SearchField
          hideLabel
          label="Search your trail"
          placeholder="Search your trail"
          size="large"
          trailing={<Badge tone="outline">⌘ K</Badge>}
        />
      </Stack>
    ),
  },
};
