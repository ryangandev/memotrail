const { Button, EmptyState, Icon } = MemoTrail;

// The same states the Web and iOS galleries show.
export const specimens = {
  "empty-state-with-action": {
    title: "With an icon and an action",
    render: () => (
      <EmptyState
        actions={<Button>New Entry</Button>}
        description="Write one from the dock, or bring notes in with Import."
        icon={<Icon name="archive" size={20} />}
        title="Entries you save appear here"
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
        icon={<Icon name="star" size={20} />}
        onClick={() => {}}
        title="Start with a first worth remembering"
      />
    ),
  },
};
