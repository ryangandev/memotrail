const { SeparatedList } = MemoTrail;

export const specimens = {
  "separated-list-default": {
    title: "Facts that wrap whole",
    render: () => (
      <div style={{ maxWidth: 320, color: "var(--mt-color-ink-muted)" }}>
        <SeparatedList>
          <span>Sep 18, 2026</span>
          <span>Lisbon</span>
          <span>3 photos</span>
          <span>2 tags</span>
          <span>Edited yesterday</span>
        </SeparatedList>
      </div>
    ),
  },
  "separated-list-end-aligned": {
    title: "End aligned, with word spacing",
    render: () => (
      <div style={{ maxWidth: 320, color: "var(--mt-color-ink-muted)" }}>
        <SeparatedList align="end" spacing="word">
          <span>Since 2019</span>
          <span>12 entries</span>
          <span>Present</span>
        </SeparatedList>
      </div>
    ),
  },
};
