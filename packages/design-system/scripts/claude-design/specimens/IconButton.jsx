import { iconButtonSizes, iconButtonVariants } from "./generated.js";
import { Row } from "./runtime.jsx";

const { Icon, IconButton } = MemoTrail;

// The action each variant suits. A variant added to icon-button.yaml shows a plus until it gets one.
const samples = {
  primary: ["plus", "Add entry"],
  secondary: ["edit", "Edit entry"],
  ghost: ["more", "More actions for Travel"],
  danger: ["trash", "Move entry to Trash"],
};

const caption = {
  color: "var(--mt-color-ink-muted)",
  fontFamily: "var(--mt-font-family-mono)",
  fontSize: "var(--mt-font-size-fine)",
};

export const specimens = {
  "icon-button-variants": {
    title: "Every variant at the default medium size",
    render: () => (
      <Row>
        {iconButtonVariants.map((variant) => {
          const [icon, label] = samples[variant] ?? ["plus", variant];
          return (
            <IconButton key={variant} label={label} variant={variant}>
              <Icon name={icon} size={18} />
            </IconButton>
          );
        })}
      </Row>
    ),
  },
  "icon-button-sizes": {
    title: "Every size in the ghost variant",
    render: () => (
      <Row align="end">
        {iconButtonSizes.map((size) => (
          <span
            key={size}
            style={{
              display: "grid",
              justifyItems: "center",
              gap: "var(--mt-space-2)",
            }}
          >
            <IconButton label={`Close entry editor, ${size}`} size={size}>
              <Icon name="close" size={size === "small" ? 16 : 18} />
            </IconButton>
            <span style={caption}>{size}</span>
          </span>
        ))}
      </Row>
    ),
  },
  "icon-button-states": {
    title: "At rest, disabled, and loading",
    render: () => (
      <Row>
        <IconButton label="Add entry">
          <Icon name="plus" size={18} />
        </IconButton>
        <IconButton disabled label="Add entry">
          <Icon name="plus" size={18} />
        </IconButton>
        <IconButton loading label="Saving entry">
          <Icon name="plus" size={18} />
        </IconButton>
      </Row>
    ),
  },
};
