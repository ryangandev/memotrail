import { pageFrameVariants, tokens } from "./generated.js";

const { PageFrame } = MemoTrail;

// Each frame at its real maximum width, in a track that scrolls inside the card.
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

export const specimens = {
  "page-frame-widths": {
    title: "Every width variant at its maximum width",
    render: () => (
      <div style={track}>
        <div style={rows}>
          {pageFrameVariants.map((variant) => (
            <PageFrame key={variant} style={sample} variant={variant}>
              <strong>{variant}</strong>
              <span
                style={{
                  color: "var(--mt-color-ink-muted)",
                  fontSize: "var(--mt-font-size-caption)",
                }}
              >
                {tokens.layout.pageWidth[variant]}px ·{" "}
                {tokens.descriptions[`layout.pageWidth.${variant}`]}
              </span>
            </PageFrame>
          ))}
        </div>
      </div>
    ),
  },
};
