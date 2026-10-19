const { Button, EmptyState, Icon } = MemoTrail;

// The same states the Web and iOS galleries show.
export const specimens = {
  "empty-state-with-action": {
    title: "With an icon and an action",
    render: () => (
      <EmptyState
        actions={<Button>Add your first memory</Button>}
        description="Capture a memory to begin building your trail."
        icon={<Icon name="plus" size={24} />}
        title="Your Life Wiki is empty"
      />
    ),
  },
  "empty-state-informational": {
    title: "Informational, without an icon or action",
    render: () => (
      <EmptyState
        description="Photos you add to this Entry appear here."
        headingLevel={3}
        title="No photos yet"
      />
    ),
  },
  "empty-state-button": {
    title: "The whole state as one button",
    render: () => (
      <EmptyState
        description="Add the first time you did something new."
        icon={<Icon name="star" size={24} />}
        onClick={() => {}}
        title="Start with a first worth remembering"
      />
    ),
  },
};
