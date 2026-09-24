import { getTimelineWorkspace } from "@/lib/data/timeline";
import { TimelineIdeaFrame } from "../_shared/idea-frame";
import { createTimelineIdeaModel } from "../_shared/model";
import { ChaptersTimeline } from "./chapters-timeline";

export const dynamic = "force-dynamic";

const path = "/timeline/ideas/chapters";

export default async function ChaptersPage() {
  const workspace = await getTimelineWorkspace();
  if (!workspace) return null;
  const model = createTimelineIdeaModel(workspace.tracks);

  return (
    <TimelineIdeaFrame
      description="Read your moments as a book, with recorded years gathered into collapsible sections."
      eyebrow="08 / Chapters"
      model={model}
      path={path}
      title="A Life in Chapters"
      workspace={workspace}
    >
      <ChaptersTimeline model={model} path={path} />
    </TimelineIdeaFrame>
  );
}
