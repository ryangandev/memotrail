import { Stack } from "./runtime.jsx";

const { SearchField } = MemoTrail;

const key = {
  padding: "var(--mt-space-0-75) var(--mt-space-1-75)",
  border: "var(--mt-size-stroke-thin) solid var(--mt-color-border)",
  borderRadius: "var(--mt-radius-xsmall)",
  color: "var(--mt-color-ink-muted)",
  background: "var(--mt-color-surface-subtle)",
  fontFamily: "var(--mt-font-family-sans)",
  fontSize: "var(--mt-font-size-micro)",
};

export const specimens = {
  "search-field-sizes": {
    title: "Small, medium, and large",
    render: () => (
      <Stack width="420px">
        <SearchField
          label="Compact search"
          placeholder="Search your Entries"
          size="small"
        />
        <SearchField
          label="Search Locations"
          placeholder="Search for an address"
        />
        <SearchField
          label="Search Library"
          placeholder="A phrase, date, or question about your life..."
          size="large"
        />
      </Stack>
    ),
  },
  "search-field-hidden-label": {
    title: "Hidden label, with a shortcut hint",
    render: () => (
      <Stack width="420px">
        <SearchField
          hideLabel
          label="Search MemoTrail"
          placeholder="Search Entries or go somewhere..."
          size="large"
          trailing={
            <kbd aria-hidden="true" style={key}>
              esc
            </kbd>
          }
        />
      </Stack>
    ),
  },
  "search-field-disabled": {
    title: "Disabled",
    render: () => (
      <Stack width="420px">
        <SearchField
          disabled
          label="Disabled search"
          placeholder="Search unavailable"
        />
      </Stack>
    ),
  },
};
