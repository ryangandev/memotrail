import { imageFits } from "./generated.js";
import { Note, Stack } from "./runtime.jsx";

const { ProgressiveImage, Skeleton } = MemoTrail;

// The galleries' drawn coast landscape stands in for a photo, so the preview needs no network.
const landscape = `data:image/svg+xml,${encodeURIComponent(
  `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360" viewBox="0 0 640 360"><rect width="640" height="360" fill="#DDE8E1"/><path d="M0 285 190 115l112 95 90-72 248 147v75H0Z" fill="#82AD98"/><circle cx="492" cy="92" r="38" fill="#A76346"/></svg>`,
)}`;
// The landscape turned upright, so cover and contain crop it differently in a wide frame.
const tall = `data:image/svg+xml,${encodeURIComponent(
  `<svg xmlns="http://www.w3.org/2000/svg" width="360" height="640" viewBox="0 0 360 640"><rect width="360" height="640" fill="#DDE8E1"/><path d="M0 506 107 204l63 169 51-128 139 261v134H0Z" fill="#82AD98"/><circle cx="277" cy="164" r="38" fill="#A76346"/></svg>`,
)}`;

const grid = {
  display: "grid",
  gridTemplateColumns: "repeat(3, minmax(0, 1fr))",
  gap: "var(--mt-space-3)",
};

const tile = {
  position: "relative",
  aspectRatio: "16 / 9",
  overflow: "hidden",
  borderRadius: "var(--mt-radius-medium)",
};

function Tile({ children, label }) {
  return (
    <Stack gap="var(--mt-space-2)">
      <div style={tile}>{children}</div>
      <Note>{label}</Note>
    </Stack>
  );
}

// The same photos the Web and iOS galleries show.
export const specimens = {
  "image-states": {
    title: "Loaded, loading, and failed",
    render: () => (
      <div style={grid}>
        <Tile label="Loaded">
          <ProgressiveImage alt="Coast" src={landscape} />
        </Tile>
        <Tile label="Loading">
          <Skeleton shape="fill" />
        </Tile>
        <Tile label="Failed">
          <ProgressiveImage
            alt="Unavailable photo"
            src="data:image/png;base64,AA=="
          />
        </Tile>
      </div>
    ),
  },
  "image-fit": {
    title: "A tall photo in a wide frame, cropped and whole",
    render: () => (
      <div style={grid}>
        {imageFits.map((fit) => (
          <Tile key={fit} label={fit}>
            <ProgressiveImage alt="Lighthouse" fit={fit} src={tall} />
          </Tile>
        ))}
      </div>
    ),
  },
};
