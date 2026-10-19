import { Stack } from "./runtime.jsx";

const { EntryRow, EntryRowGroup, EntryRowList } = MemoTrail;

// The galleries' drawn coast landscape stands in for a photo, so the preview needs no network.
const landscape = `data:image/svg+xml,${encodeURIComponent(
  `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360" viewBox="0 0 640 360"><rect width="640" height="360" fill="#DDE8E1"/><path d="M0 285 190 115l112 95 90-72 248 147v75H0Z" fill="#82AD98"/><circle cx="492" cy="92" r="38" fill="#A76346"/></svg>`,
)}`;

// A wide and a phone-width frame, so the narrow list shows its stacked date.
function Frames({ children }) {
  return (
    <Stack gap="var(--mt-space-6)">
      {[720, 342].map((width) => (
        <div key={width} style={{ width: "100%", maxWidth: width }}>
          {children}
        </div>
      ))}
    </Stack>
  );
}

function LibraryRows() {
  return (
    <>
      <EntryRowGroup headingLevel={3} label="October 2026">
        <EntryRow
          date="Oct 17"
          dateTime="2026-10-17"
          excerpt="Four interviews back to back. The last one felt like a conversation instead of a test."
          href="#entry-row"
          tags={["career", "nyc"]}
          title="Final round at the design studio"
        />
        <EntryRow
          date={null}
          dateTime="2026-10-15"
          excerpt="Walked the long way home and watched the light go orange over the river."
          href="#entry-row"
          title="Thursday, October 15, 2026"
        />
        <EntryRow
          date="Oct 14"
          dateTime="2026-10-14"
          excerpt="Dumplings from scratch. Took four hours and every pleat was uneven."
          href="#entry-row"
          isFirstTime
          tags={["cooking", "friends"]}
          thumbnail={{ alt: "The table set for twelve", src: landscape }}
          title="Cooking for twelve people"
        />
      </EntryRowGroup>
      <EntryRowGroup headingLevel={3} label="January 2026">
        <EntryRow
          date="Jan 2026 - now"
          dateTime="2026-01"
          excerpt="Leaving consulting and looking for work that makes things."
          href="#entry-row"
          isChapter
          title="2026 job search"
        />
      </EntryRowGroup>
      <EntryRowGroup headingLevel={3} label="September 2025">
        <EntryRow
          date="Fall 2025"
          dateTime="2025-09"
          excerpt="Bouldering twice a week, mostly falling."
          href="#entry-row"
          isFirstTime
          title="Learning to climb"
        />
      </EntryRowGroup>
    </>
  );
}

// The same rows the Web gallery shows. EntryRow is Web only.
export const specimens = {
  "entry-row-default": {
    title: "Library rows by month, wide and narrow",
    render: () => (
      <Frames>
        <LibraryRows />
      </Frames>
    ),
  },
  "entry-row-compact": {
    title: "Compact rows and a search match",
    render: () => (
      <Stack gap="var(--mt-space-6)">
        <div style={{ maxWidth: 720 }}>
          <EntryRowList label="Entries in this Chapter">
            <EntryRow
              date="Oct 17"
              dateTime="2026-10-17"
              href="#entry-row"
              title="Final round at the design studio"
              variant="compact"
            />
            <EntryRow
              date="Sep 30"
              dateTime="2026-09-30"
              href="#entry-row"
              isFirstTime
              title="First offer, turned down"
              variant="compact"
            />
          </EntryRowList>
        </div>
        <div style={{ maxWidth: 720 }}>
          <EntryRowList label="Search results">
            <EntryRow
              date="Jul 9, 2017"
              dateTime="2017-07-09"
              excerpt={
                <>
                  …the old <mark>lantern</mark> on the porch still worked after
                  the storm…
                </>
              }
              href="#entry-row"
              matchReasons={["Title", "Body"]}
              title="The lantern on the porch"
            />
          </EntryRowList>
        </div>
      </Stack>
    ),
  },
};
