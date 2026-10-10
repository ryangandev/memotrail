import { Row } from "./runtime.jsx";

const { Icon } = MemoTrail;

// The exporter defines ICON_NAMES from the Web icons in icons.json.
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

export const specimens = {
  "icon-set": {
    title: "Every Web icon at 20px",
    render: () => (
      <div style={grid}>
        {ICON_NAMES.map((name) => (
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
      <Row>
        {[14, 16, 18, 24].map((size) => (
          <Icon key={size} name="calendar" size={size} />
        ))}
      </Row>
    ),
  },
};
