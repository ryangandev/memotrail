const { Button, SectionHeader } = MemoTrail;

export const specimens = {
  "section-header-section": {
    title: "Section: a serif title with a description and an action",
    render: () => (
      <SectionHeader
        action={
          <Button size="small" variant="secondary">
            View all
          </Button>
        }
        description="Entries you saved most recently."
        title="Recent Entries"
      />
    ),
  },
  "section-header-list": {
    title: "List: the uppercase heading above a list, with a count",
    render: () => (
      <SectionHeader
        detail="3"
        detailAlign="end"
        headingLevel={3}
        title="Needs organizing"
        variant="list"
      />
    ),
  },
};
