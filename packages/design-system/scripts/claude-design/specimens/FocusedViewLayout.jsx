const { Badge, Button, EmptyState, FocusedViewLayout, Icon, SeparatedList } =
  MemoTrail;

export const specimens = {
  "focused-view-layout-default": {
    title: "A focused view with a summary and content",
    render: () => (
      <FocusedViewLayout
        actions={
          <Button>
            <Icon name="plus" size={16} />
            Add First Time
          </Button>
        }
        description="The small beginnings worth finding again."
        eyebrow="Focused view"
        summary={
          <SeparatedList>
            <Badge tone="neutral">2 First Times</Badge>
            <Badge tone="accent">1 this year</Badge>
          </SeparatedList>
        }
        summaryLabel="First Times summary"
        title="First Times"
      >
        <EmptyState
          description="First Times you add will appear here."
          headingLevel={3}
          title="Nothing here yet"
        />
      </FocusedViewLayout>
    ),
  },
};
