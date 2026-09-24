import { getTimelineWorkspace } from "@/lib/data/timeline";
import { TimelineIdeaFrame } from "../_shared/idea-frame";
import { createTimelineIdeaModel } from "../_shared/model";
import { MinimalIndexTimeline } from "./minimal-index-timeline";

export const dynamic = "force-dynamic";

const path = "/timeline/ideas/minimal-index";

export default async function MinimalIndexPage() {
  const workspace = await getTimelineWorkspace();
  if (!workspace) return null;
  const model = createTimelineIdeaModel(workspace.tracks);

  return (
    <TimelineIdeaFrame
      description="A quiet chronological index of the moments and periods you chose to keep."
      eyebrow="18 / Minimal Index"
      model={model}
      path={path}
      title="A Life, Typeset"
      workspace={workspace}
    >
      <MinimalIndexTimeline model={model} path={path} />
    </TimelineIdeaFrame>
  );
}
