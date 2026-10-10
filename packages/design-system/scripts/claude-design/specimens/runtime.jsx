// Shared by every preview card. The frame provides React, ReactDOM, and MemoTrail as globals,
// and the tokens and bundle CSS, so specimens only arrange real components.

const captionStyle = {
  margin: 0,
  color: "var(--mt-color-ink-muted)",
  fontFamily: "var(--mt-type-caption-font-family)",
  fontSize: "var(--mt-type-caption-font-size)",
  fontWeight: "var(--mt-type-caption-font-weight)",
  lineHeight: "var(--mt-type-caption-line-height)",
};

export function Row({ children, align = "center" }) {
  return (
    <div
      style={{
        display: "flex",
        flexWrap: "wrap",
        alignItems: align,
        gap: "var(--mt-space-3)",
      }}
    >
      {children}
    </div>
  );
}

export function Stack({ children, gap = "var(--mt-space-4)", width }) {
  return (
    <div style={{ display: "grid", gap, maxWidth: width }}>{children}</div>
  );
}

export function Note({ children }) {
  return <p style={captionStyle}>{children}</p>;
}

export function mount(specimens, order) {
  ReactDOM.createRoot(document.getElementById("root")).render(
    <div
      style={{
        display: "grid",
        gap: "var(--mt-space-6)",
        padding: "var(--mt-space-5)",
      }}
    >
      {order.map(({ id, caption }) => (
        <section
          data-specimen={id}
          key={id}
          style={{ display: "grid", gap: "var(--mt-space-3)" }}
        >
          <p style={captionStyle}>{caption}</p>
          {specimens[id].render()}
        </section>
      ))}
    </div>,
  );
}
