import { getTimelineWorkspace } from "@/lib/data/timeline";
import { TimelineIdeaFrame } from "../_shared/idea-frame";
import { createTimelineIdeaModel } from "../_shared/model";
import { SwimlaneTimeline } from "./swimlane-timeline";

export const dynamic = "force-dynamic";

const path = "/timeline/ideas/swimlane";

export default async function SwimlanePage() {
  const workspace = await getTimelineWorkspace();
  if (!workspace) return null;
  const model = createTimelineIdeaModel(workspace.tracks);

  return (
    <TimelineIdeaFrame
      description="Compare the moments and periods of each track against one shared time axis."
      eyebrow="03 / Swimlane"
      model={model}
      path={path}
      title="Swimlane Timeline"
      workspace={workspace}
    >
      <SwimlaneTimeline
        birthDate={workspace.birthDate}
        model={model}
        path={path}
      />
    </TimelineIdeaFrame>
  );
}
