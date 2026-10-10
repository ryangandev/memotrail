const { Button, EmptyState, Icon } = MemoTrail;

export const specimens = {
  "empty-state-with-action": {
    title: "With an icon and an action",
    render: () => (
      <EmptyState
        actions={
          <Button size="small">
            <Icon name="plus" size={16} />
            New entry
          </Button>
        }
        description="Entries you save to Library will appear here, ready to return to."
        icon={<Icon name="sparkle" size={22} />}
        title="Your trail starts here"
      />
    ),
  },
  "empty-state-informational": {
    title: "Informational, without an action",
    render: () => (
      <EmptyState
        description="As your archive grows, an older dated Entry will find its way back here."
        headingLevel={3}
        title="Room for a memory"
      />
    ),
  },
  "empty-state-button": {
    title: "The whole state as one button",
    render: () => (
      <EmptyState
        description="The home you live in, the vehicle you drive, and the Periods still going on will appear here."
        onClick={() => {}}
        title="Life is still unfolding"
      />
    ),
  },
};
