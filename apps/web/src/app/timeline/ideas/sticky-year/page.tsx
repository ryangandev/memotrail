import { getTimelineWorkspace } from "@/lib/data/timeline";
import { TimelineIdeaFrame } from "../_shared/idea-frame";
import { createTimelineIdeaModel } from "../_shared/model";
import { StickyYearTimeline } from "./sticky-year-timeline";

export const dynamic = "force-dynamic";

const path = "/timeline/ideas/sticky-year";

export default async function StickyYearPage() {
  const workspace = await getTimelineWorkspace();
  if (!workspace) return null;
  const model = createTimelineIdeaModel(workspace.tracks);

  return (
    <TimelineIdeaFrame
      description="Move through your recorded years while the year stays in view."
      eyebrow="07 / Sticky Year"
      model={model}
      path={path}
      title="Sticky-Year Feed"
      workspace={workspace}
    >
      <StickyYearTimeline model={model} path={path} />
    </TimelineIdeaFrame>
  );
}
