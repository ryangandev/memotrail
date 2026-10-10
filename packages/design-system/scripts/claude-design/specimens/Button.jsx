import { Row } from "./runtime.jsx";

const { Button, ButtonLink, Icon } = MemoTrail;

const variants = [
  ["primary", "Save to Library"],
  ["secondary", "Cancel"],
  ["ghost", "Edit"],
  ["danger", "Move to Trash"],
];

export const specimens = {
  "button-variants": {
    title: "Every variant at the default medium size",
    render: () => (
      <Row>
        {variants.map(([variant, label]) => (
          <Button key={variant} variant={variant}>
            {label}
          </Button>
        ))}
      </Row>
    ),
  },
  "button-disabled": {
    title: "Every variant disabled",
    render: () => (
      <Row>
        {variants.map(([variant, label]) => (
          <Button disabled key={variant} variant={variant}>
            {label}
          </Button>
        ))}
      </Row>
    ),
  },
  "button-loading": {
    title: "Every variant loading",
    render: () => (
      <Row>
        {variants.map(([variant]) => (
          <Button key={variant} loading variant={variant}>
            Saving
          </Button>
        ))}
      </Row>
    ),
  },
  "button-sizes": {
    title: "Every size in the secondary variant, with a leading icon",
    render: () => (
      <Row>
        {["small", "medium", "large"].map((size) => (
          <Button key={size} size={size} variant="secondary">
            <Icon name="plus" size={size === "small" ? 14 : 16} />
            Add tag
          </Button>
        ))}
      </Row>
    ),
  },
  "button-link": {
    title: "Navigation drawn as a button with ButtonLink",
    render: () => (
      <Row>
        <ButtonLink href="#library">
          <Icon name="arrowLeft" size={16} />
          Back to Library
        </ButtonLink>
        <ButtonLink href="#timeline" variant="primary">
          Open Timeline
        </ButtonLink>
        <ButtonLink href="#settings" variant="ghost">
          Settings
        </ButtonLink>
      </Row>
    ),
  },
};
