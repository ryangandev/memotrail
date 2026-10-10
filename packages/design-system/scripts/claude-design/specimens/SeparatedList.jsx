import { Stack } from "./runtime.jsx";

const { SeparatedList } = MemoTrail;

// Outlined frames, so each list's wrapping shows as the frame narrows.
const frame = {
  maxWidth: "100%",
  padding: "var(--mt-space-4)",
  border: "var(--mt-size-stroke-thin) dashed var(--mt-color-border-strong)",
  borderRadius: "var(--mt-radius-medium)",
  color: "var(--mt-color-ink-faint)",
  fontSize: "var(--mt-font-size-caption)",
};

const link = { color: "var(--mt-color-accent)" };

function Frames({ children }) {
  return (
    <Stack gap="var(--mt-space-3)">
      {[null, 240, 150].map((width) => (
        <div key={width ?? "wide"} style={{ ...frame, width: width ?? "auto" }}>
          {children}
        </div>
      ))}
    </Stack>
  );
}

// The same lists the Web and iOS galleries show.
export const specimens = {
  "separated-list-default": {
    title: "Facts and links that wrap whole",
    render: () => (
      <Frames>
        <SeparatedList>
          <a href="#separated-list" style={link}>
            Manage tracks
          </a>
          <span>8 tracks</span>
          <span>12 moments</span>
          <span>2017 to 2026</span>
        </SeparatedList>
      </Frames>
    ),
  },
  "separated-list-word": {
    title: "Word spacing, reading like a sentence",
    render: () => (
      <Frames>
        <SeparatedList spacing="word">
          <span>First Time</span>
          <span>3 earlier versions</span>
          <span>In Trash</span>
        </SeparatedList>
      </Frames>
    ),
  },
  "separated-list-end-aligned": {
    title: "Attribution that shares the trailing edge",
    render: () => (
      <Frames>
        <SeparatedList align="end">
          <span>
            Powered by{" "}
            <a href="#separated-list" style={link}>
              Geoapify
            </a>
          </span>
          <a href="#separated-list" style={link}>
            © OpenStreetMap contributors
          </a>
        </SeparatedList>
      </Frames>
    ),
  },
};
