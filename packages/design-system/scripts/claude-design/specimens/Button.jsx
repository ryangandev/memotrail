import { buttonSizes, buttonVariants } from "./generated.js";
import { Row } from "./runtime.jsx";

const { Button, ButtonLink, Icon } = MemoTrail;

// A real label for each variant. A variant added to button.yaml shows its own name until it gets
// one here.
const labels = {
  primary: "Save changes",
  secondary: "Cancel",
  quiet: "Edit",
  danger: "Move to Trash",
};
const variants = buttonVariants.map((variant) => [
  variant,
  labels[variant] ?? variant,
]);

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
        {buttonSizes.map((size) => (
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
        <ButtonLink href="#library" variant="secondary">
          <Icon name="arrowLeft" size={16} />
          Back to Library
        </ButtonLink>
        <ButtonLink href="#timeline" variant="primary">
          Open Timeline
        </ButtonLink>
        <ButtonLink href="#settings" variant="quiet">
          Settings
        </ButtonLink>
      </Row>
    ),
  },
};
