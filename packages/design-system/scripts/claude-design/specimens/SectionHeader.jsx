import { Stack } from "./runtime.jsx";

const { Button, Icon, SectionHeader } = MemoTrail;

const link = {
  display: "inline-flex",
  alignItems: "center",
  gap: "var(--mt-space-1)",
  color: "var(--mt-color-accent)",
  fontSize: "var(--mt-font-size-caption)",
  textDecoration: "none",
  whiteSpace: "nowrap",
};

const viewAll = (
  <a href="#section-header" style={link}>
    View all
    <Icon name="chevron" size={14} />
  </a>
);

// The same headers the Web and iOS galleries show.
export const specimens = {
  "section-header-section": {
    title: "Section headers with a count, a description, and an action",
    render: () => (
      <Stack>
        <SectionHeader detail="12 entries" title="Recent Entries" />
        <SectionHeader
          action={
            <Button size="small" variant="secondary">
              Edit
            </Button>
          }
          description="Pinned to the top of your Library."
          title="Favorites"
        />
        <SectionHeader action={viewAll} title="A memory for today" />
      </Stack>
    ),
  },
  "section-header-list": {
    title: "List headers with a count at the title and at the far edge",
    render: () => (
      <Stack>
        <SectionHeader detail="12 items" title="All items" variant="list" />
        <SectionHeader
          action={
            <a href="#section-header" style={link}>
              3 need organizing
            </a>
          }
          detail="12 items"
          detailAlign="end"
          title="All items"
          variant="list"
        />
      </Stack>
    ),
  },
  "section-header-long": {
    title: "A long title in a narrow column",
    render: () => (
      <div style={{ width: 240 }}>
        <SectionHeader
          action={viewAll}
          title="Letters, photos, and notes from the summer at the coast house"
        />
      </div>
    ),
  },
};
