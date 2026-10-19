const {
  Badge,
  Icon,
  ProgressiveImage,
  RecordCard,
  RecordCardBody,
  RecordCardVisual,
} = MemoTrail;

// The layout inside the card belongs to each record view. These styles follow the First Times
// view, with the same tokens it uses.
const landscape = `data:image/svg+xml,${encodeURIComponent(
  `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360" viewBox="0 0 640 360"><rect width="640" height="360" fill="#DDE8E1"/><path d="M0 285 190 115l112 95 90-72 248 147v75H0Z" fill="#82AD98"/><circle cx="492" cy="92" r="38" fill="#A76346"/></svg>`,
)}`;

const mark = {
  display: "flex",
  height: "100%",
  flexDirection: "column",
  alignItems: "flex-start",
  justifyContent: "flex-end",
  gap: "var(--mt-space-3)",
  padding: "var(--mt-space-5)",
  color: "var(--mt-color-accent)",
  background:
    "radial-gradient(circle at 78% 24%, var(--mt-color-accent-subtle), transparent 34%), linear-gradient(135deg, var(--mt-color-surface), var(--mt-color-surface-subtle))",
};

const markLabel = {
  color: "var(--mt-color-ink-muted)",
  fontFamily: "var(--mt-font-family-serif)",
  fontSize: "var(--mt-font-size-title-small)",
};

const dates = {
  display: "flex",
  alignItems: "center",
  justifyContent: "space-between",
  gap: "var(--mt-space-3)",
  color: "var(--mt-color-ink-faint)",
  fontFamily: "var(--mt-type-date-stamp-font-family)",
  fontSize: "var(--mt-type-date-stamp-font-size)",
  letterSpacing: "var(--mt-type-date-stamp-letter-spacing)",
  textTransform: "var(--mt-type-date-stamp-text-transform)",
};

const title = {
  margin: "var(--mt-space-2) 0 0",
  fontFamily: "var(--mt-type-record-card-title-font-family)",
  fontSize: "var(--mt-type-record-card-title-font-size)",
  fontWeight: "var(--mt-type-record-card-title-font-weight)",
  letterSpacing: "var(--mt-type-record-card-title-letter-spacing)",
  lineHeight: "var(--mt-type-record-card-title-line-height)",
};

const factStyle = {
  display: "flex",
  alignItems: "center",
  gap: "var(--mt-space-1-5)",
  margin: "var(--mt-space-2) 0 0",
  color: "var(--mt-color-ink-muted)",
  fontSize: "var(--mt-font-size-caption)",
};

const footer = {
  display: "flex",
  minHeight: "var(--mt-size-record-card-footer-height)",
  alignItems: "flex-end",
  justifyContent: "space-between",
  gap: "var(--mt-space-3)",
  marginTop: "var(--mt-space-4)",
  paddingTop: "var(--mt-space-3)",
  borderTop: "var(--mt-size-stroke-thin) solid var(--mt-color-border)",
  color: "var(--mt-color-ink-faint)",
};

const corner = (place) => ({
  position: "absolute",
  ...(place === "top"
    ? { top: "var(--mt-space-3)", left: "var(--mt-space-3)" }
    : { right: "var(--mt-space-3)", bottom: "var(--mt-space-3)" }),
});

function Fields({ date, fact, tags, name }) {
  return (
    <RecordCardBody>
      <div style={dates}>
        <time style={{ color: "var(--mt-color-accent)" }}>{date}</time>
      </div>
      <h3 style={title}>{name}</h3>
      {fact ? (
        <p style={factStyle}>
          <Icon name={fact.icon} size={14} />
          {fact.text}
        </p>
      ) : null}
      <div style={footer}>
        <div
          style={{
            display: "flex",
            flexWrap: "wrap",
            gap: "var(--mt-space-1-25)",
          }}
        >
          {tags.map((tag) => (
            <Badge key={tag} size="micro" tone="neutral">
              #{tag}
            </Badge>
          ))}
        </div>
        <Icon name="chevron" size={15} />
      </div>
    </RecordCardBody>
  );
}

const cards = {
  display: "grid",
  gridTemplateColumns: "repeat(2, minmax(0, 1fr))",
  gap: "var(--mt-space-5)",
};

// The same kind of records the Web gallery shows.
export const specimens = {
  "record-card-photo": {
    title: "A First Time with a cover photo",
    render: () => (
      <div style={cards}>
        <RecordCard
          ariaLabel="First solo hike, Jun 12, 2021"
          onClick={() => {}}
        >
          <RecordCardVisual>
            <ProgressiveImage alt="" src={landscape} />
            <span style={corner("bottom")}>
              <Badge size="micro" tone="inverse" uppercase>
                3 photos
              </Badge>
            </span>
          </RecordCardVisual>
          <Fields
            date="Jun 12, 2021"
            fact={{ icon: "map", text: "Mount Hood, Oregon, United States" }}
            name="First solo hike"
            tags={["hiking"]}
          />
        </RecordCard>
      </div>
    ),
  },
  "record-card-mark": {
    title: "A First Time with its mark",
    render: () => (
      <div style={cards}>
        <RecordCard ariaLabel="First bike ride, 2012" onClick={() => {}}>
          <RecordCardVisual>
            <div style={mark}>
              <Icon name="star" size={24} />
              <span style={markLabel}>First bike ride</span>
            </div>
          </RecordCardVisual>
          <Fields date="2012" name="First bike ride" tags={["cycling"]} />
        </RecordCard>
      </div>
    ),
  },
};
