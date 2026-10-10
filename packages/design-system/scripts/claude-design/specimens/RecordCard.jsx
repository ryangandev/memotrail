const { Badge, Icon, RecordCard, RecordCardBody, RecordCardVisual } = MemoTrail;

// The layout inside the card belongs to each record view. These styles follow the Vehicles view
// with the same tokens it uses.
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
    "radial-gradient(circle at 78% 24%, var(--mt-color-accent-subtle), transparent 34%)",
};

const markLabel = {
  color: "var(--mt-color-ink-muted)",
  fontFamily: "var(--mt-font-family-serif)",
  fontSize: "var(--mt-font-size-title-small)",
};

const dates = {
  display: "flex",
  justifyContent: "space-between",
  gap: "var(--mt-space-3)",
  color: "var(--mt-color-ink-faint)",
  fontFamily: "var(--mt-font-family-mono)",
  fontSize: 10,
  letterSpacing: "0.025em",
  textTransform: "uppercase",
};

const title = {
  margin: "var(--mt-space-2) 0 0",
  fontFamily: "var(--mt-font-family-serif)",
  fontSize: "var(--mt-font-size-title)",
  fontWeight: "var(--mt-font-weight-medium)",
  letterSpacing: "-0.02em",
  lineHeight: "var(--mt-line-height-tight)",
};

const fact = {
  display: "flex",
  alignItems: "center",
  gap: 6,
  margin: "var(--mt-space-2) 0 0",
  color: "var(--mt-color-ink-muted)",
  fontSize: "var(--mt-font-size-caption)",
};

const footer = {
  display: "flex",
  minHeight: 31,
  alignItems: "flex-end",
  justifyContent: "space-between",
  gap: "var(--mt-space-3)",
  marginTop: "var(--mt-space-4)",
  paddingTop: "var(--mt-space-3)",
  borderTop: "1px solid var(--mt-color-border)",
  color: "var(--mt-color-ink-faint)",
};

export const specimens = {
  "record-card-default": {
    title: "A Vehicle card: a visual with a status badge, then the body",
    render: () => (
      <div style={{ maxWidth: 320 }}>
        <RecordCard ariaLabel="Open Blue Civic" onClick={() => {}}>
          <RecordCardVisual>
            <div style={mark}>
              <Icon name="car" size={24} />
              <span style={markLabel}>Honda Civic</span>
            </div>
            <span
              style={{
                position: "absolute",
                top: "var(--mt-space-3)",
                left: "var(--mt-space-3)",
              }}
            >
              <Badge size="micro" tone="glassAccent" uppercase>
                Current
              </Badge>
            </span>
          </RecordCardVisual>
          <RecordCardBody>
            <div style={dates}>
              <time style={{ color: "var(--mt-color-accent)" }}>
                Since 2019
              </time>
              <span>About 7 years</span>
            </div>
            <h3 style={title}>Blue Civic</h3>
            <p style={fact}>
              <Icon name="car" size={14} />
              Honda Civic
            </p>
            <div style={footer}>
              <div style={{ display: "flex", flexWrap: "wrap", gap: 5 }}>
                <Badge size="micro" tone="neutral">
                  #commute
                </Badge>
                <Badge size="micro" tone="neutral">
                  #roadtrips
                </Badge>
              </div>
              <Icon name="chevron" size={15} />
            </div>
          </RecordCardBody>
        </RecordCard>
      </div>
    ),
  },
};
