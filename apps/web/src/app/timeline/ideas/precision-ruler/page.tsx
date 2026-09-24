import { getTimelineWorkspace } from "@/lib/data/timeline";
import { createTimelineLayout } from "@/lib/data/timeline-layout";
import { TimelineIdeaFrame } from "../_shared/idea-frame";
import { createTimelineIdeaModel } from "../_shared/model";
import { PrecisionRulerTimeline } from "./precision-ruler-timeline";

export const dynamic = "force-dynamic";

const path = "/timeline/ideas/precision-ruler";

export default async function PrecisionRulerPage() {
  const workspace = await getTimelineWorkspace();
  if (!workspace) return null;
  const model = createTimelineIdeaModel(workspace.tracks);
  const layout = createTimelineLayout(
    model.items.map(({ entry }) => ({ ...entry, trackId: "all" })),
    new Date(),
    workspace.birthDate,
  );

  return (
    <TimelineIdeaFrame
      description="Zoom into recorded years and scrub across the moments of your life."
      eyebrow="19 / Precision Ruler"
      model={model}
      path={path}
      title="Precision Ruler"
      workspace={workspace}
    >
      <PrecisionRulerTimeline layout={layout} model={model} path={path} />
    </TimelineIdeaFrame>
  );
}
