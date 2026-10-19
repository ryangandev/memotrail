import { iconNames } from "./generated.js";
import { Row } from "./runtime.jsx";

const { Icon } = MemoTrail;

const grid = {
  display: "grid",
  gridTemplateColumns: "repeat(auto-fill, minmax(96px, 1fr))",
  gap: "var(--mt-space-3) var(--mt-space-2)",
};

const cell = {
  display: "grid",
  justifyItems: "center",
  gap: "var(--mt-space-1)",
  color: "var(--mt-color-ink)",
  fontSize: "var(--mt-font-size-caption)",
  textAlign: "center",
};

const caption = {
  color: "var(--mt-color-ink-muted)",
  fontFamily: "var(--mt-font-family-mono)",
  fontSize: "var(--mt-font-size-micro)",
};

const label = {
  display: "inline-flex",
  alignItems: "center",
  gap: "var(--mt-space-2)",
  fontSize: "var(--mt-font-size-label)",
  fontWeight: "var(--mt-font-weight-medium)",
};

export const specimens = {
  "icon-set": {
    title: "Every Web icon at 20px",
    render: () => (
      <div style={grid}>
        {iconNames.map((name) => (
          <span key={name} style={cell}>
            <Icon name={name} size={20} />
            <span style={{ color: "var(--mt-color-ink-muted)" }}>{name}</span>
          </span>
        ))}
      </div>
    ),
  },
  "icon-sizes": {
    title: "14, 16, 18, and 24px",
    render: () => (
      <Row align="end">
        {[14, 16, 18, 24].map((size) => (
          <span
            key={size}
            style={{ ...cell, color: "var(--mt-color-ink-muted)" }}
          >
            <Icon name="calendar" size={size} />
            <span style={caption}>{size}</span>
          </span>
        ))}
      </Row>
    ),
  },
  "icon-color": {
    title: "Ink, muted, accent, and warm text",
    render: () => (
      <Row>
        {[
          ["timeline", "Timeline", "var(--mt-color-ink)"],
          ["archive", "Library", "var(--mt-color-ink-muted)"],
          ["plus", "Add entry", "var(--mt-color-accent)"],
          ["refresh", "Retry sync", "var(--mt-color-warm)"],
        ].map(([name, text, color]) => (
          <span key={name} style={{ ...label, color }}>
            <Icon name={name} size={16} />
            {text}
          </span>
        ))}
      </Row>
    ),
  },
};
