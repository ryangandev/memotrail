import { pageFrameWidths } from "./generated.js";

const { PageFrame } = MemoTrail;

// Each frame at its real maximum width from the same left edge, in a track that scrolls inside
// the card.
const track = { maxWidth: "100%", overflowX: "auto" };

const rows = {
  display: "grid",
  width:
    "calc(var(--mt-layout-page-width-canvas) + 2 * var(--mt-layout-page-gutter-regular))",
  gap: "var(--mt-space-2)",
};

const sample = {
  display: "grid",
  margin: 0,
  gap: "var(--mt-space-1)",
  padding: "var(--mt-space-3) var(--mt-space-4)",
  border: "var(--mt-size-stroke-thin) dashed var(--mt-color-border-strong)",
  borderRadius: "var(--mt-radius-medium)",
  background: "var(--mt-color-surface)",
};

const notes = {
  reading: "720 px · an Entry page, a review, Settings, Import, and Export",
  list: "960 px · Dashboard, Library, First Times, Tags, Trash, and Reviews",
  full: "The whole workspace · Timeline",
};

export const specimens = {
  "page-frame-widths": {
    title: "Every width at its maximum width",
    render: () => (
      <div style={track}>
        <div style={rows}>
          {pageFrameWidths.map((width) => (
            <PageFrame key={width} style={sample} width={width}>
              <strong>{width}</strong>
              <span
                style={{
                  color: "var(--mt-color-ink-muted)",
                  fontSize: "var(--mt-font-size-caption)",
                }}
              >
                {notes[width]}
              </span>
            </PageFrame>
          ))}
        </div>
      </div>
    ),
  },
};
