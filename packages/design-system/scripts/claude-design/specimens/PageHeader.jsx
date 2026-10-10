const { Button, ButtonLink, Icon, PageHeader } = MemoTrail;

export const specimens = {
  "page-header-full": {
    title: "Eyebrow, title, description, and actions",
    render: () => (
      <PageHeader
        actions={
          <>
            <ButtonLink href="#timeline">Open Timeline</ButtonLink>
            <Button>
              <Icon name="plus" size={16} />
              New entry
            </Button>
          </>
        }
        description="Every Entry, Home, Vehicle, and Someday item in one place."
        eyebrow="Life Wiki"
        title="Library"
      />
    ),
  },
  "page-header-title-only": {
    title: "A second-level header with only a title",
    render: () => <PageHeader headingLevel={2} title="Settings" />,
  },
};
