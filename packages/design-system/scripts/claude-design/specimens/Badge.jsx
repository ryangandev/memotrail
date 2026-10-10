import { Row, Stack } from "./runtime.jsx";

const { Badge } = MemoTrail;

const tones = [
  ["accent", "Memory"],
  ["neutral", "Note"],
  ["warm", "First Time"],
  ["outline", "Someday"],
  ["inverse", "Home"],
  ["solidAccent", "Achieved"],
  ["glassAccent", "Current"],
  ["glassNeutral", "Vehicle"],
];

const photo = {
  display: "flex",
  flexWrap: "wrap",
  alignItems: "end",
  gap: "var(--mt-space-2)",
  minHeight: 96,
  padding: "var(--mt-space-3)",
  borderRadius: "var(--mt-radius-large)",
  background:
    "linear-gradient(135deg, var(--mt-color-accent-hover), var(--mt-color-warm))",
};

export const specimens = {
  "badge-tones": {
    title: "Every tone at the default small size",
    render: () => (
      <Row>
        {tones.map(([tone, label]) => (
          <Badge key={tone} tone={tone}>
            {label}
          </Badge>
        ))}
      </Row>
    ),
  },
  "badge-sizes": {
    title: "Every size, beside the uppercase treatment at each size",
    render: () => (
      <Stack gap="var(--mt-space-2)">
        {["micro", "small", "medium"].map((size) => (
          <Row key={size}>
            <Badge size={size}>Period</Badge>
            <Badge size={size} uppercase>
              Period
            </Badge>
          </Row>
        ))}
      </Stack>
    ),
  },
  "badge-tags": {
    title: "Tags with a leading # in Latin and CJK scripts, at the medium size",
    render: () => (
      <Row>
        <Badge size="medium" tone="neutral">
          #travel
        </Badge>
        <Badge size="medium" tone="neutral">
          #family
        </Badge>
        <Badge size="medium" tone="neutral">
          #旅行
        </Badge>
        <Badge size="medium" tone="neutral">
          #家族
        </Badge>
      </Row>
    ),
  },
  "badge-truncation": {
    title: "Long labels stay on one line and truncate in a narrow container",
    render: () => (
      <Stack gap="var(--mt-space-2)" width={180}>
        <Badge tone="outline">Weekend trips along the northern coast</Badge>
        <Badge tone="neutral">#a-very-long-tag-for-old-letters</Badge>
      </Stack>
    ),
  },
  "badge-photo-overlay": {
    title: "Uppercase micro glass and inverse tones over a photo",
    render: () => (
      <div style={photo}>
        <Badge size="micro" tone="glassAccent" uppercase>
          Current
        </Badge>
        <Badge size="micro" tone="glassNeutral" uppercase>
          Vehicle
        </Badge>
        <Badge size="micro" tone="inverse" uppercase>
          Home
        </Badge>
      </div>
    ),
  },
};
