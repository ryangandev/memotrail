const { Button, Icon, PageHeader } = MemoTrail;

// The same headers the Web and iOS galleries show.
export const specimens = {
  "page-header-full": {
    title: "Eyebrow, title, description, and actions",
    render: () => (
      <PageHeader
        actions={
          <>
            <Button variant="secondary">Filter</Button>
            <Button>
              <Icon name="plus" size={16} />
              Add memory
            </Button>
          </>
        }
        description="The moments, people, and places that make up your story."
        eyebrow="Your life, remembered"
        title="Memories"
      />
    ),
  },
  "page-header-title-only": {
    title: "A title alone",
    render: () => <PageHeader title="First sourdough loaf at home" />,
  },
};
