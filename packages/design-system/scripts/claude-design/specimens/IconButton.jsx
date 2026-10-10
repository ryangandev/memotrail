import { Row } from "./runtime.jsx";

const { Icon, IconButton } = MemoTrail;

export const specimens = {
  "icon-button-variants": {
    title: "Primary, secondary, and ghost",
    render: () => (
      <Row>
        <IconButton label="Add photos">
          <Icon name="plus" size={18} />
        </IconButton>
        <IconButton label="Search your trail" variant="secondary">
          <Icon name="search" size={18} />
        </IconButton>
        <IconButton label="Close" variant="ghost">
          <Icon name="close" size={18} />
        </IconButton>
      </Row>
    ),
  },
  "icon-button-states": {
    title: "Disabled and loading",
    render: () => (
      <Row>
        <IconButton disabled label="Add photos" variant="secondary">
          <Icon name="plus" size={18} />
        </IconButton>
        <IconButton loading label="Saving" variant="secondary">
          <Icon name="plus" size={18} />
        </IconButton>
      </Row>
    ),
  },
};
