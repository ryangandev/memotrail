import { getTimelineWorkspace } from "@/lib/data/timeline";
import { TimelineIdeaFrame } from "../_shared/idea-frame";
import { createTimelineIdeaModel } from "../_shared/model";
import { VerticalSpine } from "./vertical-spine";

export const dynamic = "force-dynamic";

const path = "/timeline/ideas/vertical-spine";

export default async function VerticalSpinePage() {
  const workspace = await getTimelineWorkspace();
  if (!workspace) return null;
  const model = createTimelineIdeaModel(workspace.tracks);

  return (
    <TimelineIdeaFrame
      description="Read moments and periods in the order they entered your life."
      eyebrow="01 / Vertical Spine"
      model={model}
      path={path}
      title="The Vertical Spine"
      workspace={workspace}
    >
      <VerticalSpine
        birthDate={workspace.birthDate}
        model={model}
        path={path}
      />
    </TimelineIdeaFrame>
  );
}
