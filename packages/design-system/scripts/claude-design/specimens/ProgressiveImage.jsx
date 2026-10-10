import { Row } from "./runtime.jsx";

const { ProgressiveImage } = MemoTrail;

// A drawn landscape stands in for a photo, so the preview needs no network.
const landscape = `data:image/svg+xml,${encodeURIComponent(
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 240"><rect width="320" height="240" fill="#DDE8E1"/><circle cx="240" cy="70" r="28" fill="#F1E2D8"/><path d="M0 190 90 110l70 60 50-40 110 90H0z" fill="#526F60"/><path d="M0 240v-30l120-50 90 50 110-40v70z" fill="#315E4F"/></svg>`,
)}`;

const tile = {
  width: 200,
  height: 150,
  borderRadius: "var(--mt-radius-medium)",
  overflow: "hidden",
};

export const specimens = {
  "progressive-image-states": {
    title: "Loaded, and a photo that failed to load",
    render: () => (
      <Row>
        <div style={tile}>
          <ProgressiveImage
            alt="A green hillside under a pale sun"
            src={landscape}
          />
        </div>
        <div style={tile}>
          <ProgressiveImage
            alt="An unavailable photo"
            src="data:image/png;base64,AA=="
          />
        </div>
      </Row>
    ),
  },
};
