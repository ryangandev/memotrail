const { Button, EmptyState, FocusedViewLayout, Icon, SeparatedList } =
  MemoTrail;

export const specimens = {
  "focused-view-layout-default": {
    title: "A focused view with a summary and content",
    render: () => (
      <FocusedViewLayout
        action={
          <Button>
            <Icon name="plus" size={16} />
            Add First Time
          </Button>
        }
        summary={
          <SeparatedList>
            <span>2 First Times</span>
            <span>1 this year</span>
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
