const { PhotoUploadProgress, ProgressiveImage } = MemoTrail;

// The galleries' drawn coast landscape, so the overlay dims a photo as it does in the app.
const landscape = `data:image/svg+xml,${encodeURIComponent(
  `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360" viewBox="0 0 640 360"><rect width="640" height="360" fill="#DDE8E1"/><path d="M0 285 190 115l112 95 90-72 248 147v75H0Z" fill="#82AD98"/><circle cx="492" cy="92" r="38" fill="#A76346"/></svg>`,
)}`;

const tile = {
  position: "relative",
  width: 132,
  height: 132,
  overflow: "hidden",
  borderRadius: "var(--mt-radius-medium)",
};

// The same progress the Web and iOS galleries show.
export const specimens = {
  "upload-progress-inline": {
    title: "Inline, under a photo field",
    render: () => <PhotoUploadProgress progress={{ completed: 3, total: 5 }} />,
  },
  "upload-progress-overlay": {
    title: "Over a photo that is uploading",
    render: () => (
      <div style={tile}>
        <ProgressiveImage alt="" src={landscape} />
        <PhotoUploadProgress
          progress={{ completed: 3, total: 5 }}
          variant="overlay"
        />
      </div>
    ),
  },
};
