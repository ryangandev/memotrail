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
            Add Vehicle
          </Button>
        }
        description="Every car, bike, and boat you have owned, with when you had it."
        eyebrow="Focused view"
        summary={
          <SeparatedList>
            <Badge tone="neutral">2 vehicles</Badge>
            <Badge tone="accent">1 current</Badge>
          </SeparatedList>
        }
        summaryLabel="Vehicle summary"
        title="Vehicles"
      >
        <EmptyState
          description="Vehicles you add will appear here."
          headingLevel={3}
          title="Nothing here yet"
        />
      </FocusedViewLayout>
    ),
  },
};
