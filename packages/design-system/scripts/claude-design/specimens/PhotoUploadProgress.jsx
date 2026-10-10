import { Row } from "./runtime.jsx";

const { PhotoUploadProgress } = MemoTrail;

// A stand-in photo: the overlay dims whatever image sits under it.
const photo = {
  position: "relative",
  width: 120,
  height: 120,
  overflow: "hidden",
  borderRadius: "var(--mt-radius-medium)",
  background:
    "linear-gradient(135deg, var(--mt-color-accent-hover), var(--mt-color-warm))",
};

export const specimens = {
  "photo-upload-progress-inline": {
    title: "Inline, under a photo field",
    render: () => <PhotoUploadProgress progress={{ completed: 2, total: 5 }} />,
  },
  "photo-upload-progress-overlay": {
    title: "Over a photo that is uploading",
    render: () => (
      <Row>
        <div style={photo}>
          <PhotoUploadProgress
            progress={{ completed: 3, total: 4 }}
            variant="overlay"
          />
        </div>
      </Row>
    ),
  },
};
