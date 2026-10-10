import { skeletonShapes } from "./generated.js";
import { Note, Stack } from "./runtime.jsx";

const { Skeleton } = MemoTrail;

// A photo-sized frame for the fill shape, which takes its whole container.
const frame = {
  position: "relative",
  width: 240,
  aspectRatio: "16 / 9",
  overflow: "hidden",
  borderRadius: "var(--mt-radius-medium)",
};

const shapes = {
  display: "grid",
  gridTemplateColumns: "repeat(2, minmax(0, 1fr))",
  alignItems: "start",
  gap: "var(--mt-space-4)",
};

const row = {
  display: "grid",
  gridTemplateColumns: "auto minmax(0, 1fr)",
  alignItems: "center",
  gap: "var(--mt-space-3)",
};

// The same placeholders the Web and iOS galleries show.
export const specimens = {
  "skeleton-shapes": {
    title: "Every shape at its default size",
    render: () => (
      <div style={shapes}>
        {skeletonShapes.map((shape) => (
          <Stack gap="var(--mt-space-2)" key={shape}>
            {shape === "fill" ? (
              <div style={frame}>
                <Skeleton shape="fill" />
              </div>
            ) : (
              <Skeleton shape={shape} />
            )}
            <Note>{shape}</Note>
          </Stack>
        ))}
      </div>
    ),
  },
  "skeleton-still": {
    title: "Still, without the shimmer",
    render: () => (
      <Stack gap="var(--mt-space-2)">
        <Skeleton animated={false} />
        <Skeleton animated={false} shape="line" />
        <Skeleton animated={false} shape="line" width="240px" />
      </Stack>
    ),
  },
  "skeleton-composed": {
    title: "A loading record row",
    render: () => (
      <Stack gap="var(--mt-space-3)">
        <div style={row}>
          <Skeleton shape="circle" />
          <Stack gap="var(--mt-space-2)">
            <Skeleton shape="line" width="160px" />
            <Skeleton shape="line" />
          </Stack>
        </div>
        <Skeleton />
      </Stack>
    ),
  },
};
