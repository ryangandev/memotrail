import { Note } from "./runtime.jsx";

const { PageFrame, PageHeader, SectionHeader } = MemoTrail;

export const specimens = {
  "page-frame-standard": {
    title: "A standard frame around a page's content",
    render: () => (
      <div
        style={{
          border: "1px dashed var(--mt-color-border-strong)",
          borderRadius: "var(--mt-radius-medium)",
        }}
      >
        <PageFrame variant="standard">
          <PageHeader eyebrow="Life Wiki" title="Library" />
          <SectionHeader detail="24" title="All items" variant="list" />
          <Note>
            compact is 880px, standard 960px, wide 1080px, and canvas 1180px.
          </Note>
        </PageFrame>
      </div>
    ),
  },
};
