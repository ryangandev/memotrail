const { Button, Icon, PageHeader } = MemoTrail;

// The same headers the Web gallery shows.
export const specimens = {
  "page-header-full": {
    title: "Back link, title, meta line, and one action",
    render: () => (
      <PageHeader
        action={
          <Button>
            <Icon name="plus" size={16} />
            New Entry
          </Button>
        }
        back="library"
        meta="Sunday, September 18"
        title="Tokyo, spring 2026"
      />
    ),
  },
  "page-header-title-only": {
    title: "A title alone",
    render: () => <PageHeader title="First sourdough loaf at home" />,
  },
};
