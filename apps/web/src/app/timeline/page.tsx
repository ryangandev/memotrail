import { TimelineWorkspace } from "@/components/timeline-workspace";
import { getTimelineWorkspace } from "@/lib/data/timeline";

export const dynamic = "force-dynamic";

export default async function TimelinePage() {
  const workspace = await getTimelineWorkspace();

  if (!workspace) {
    return null;
  }

  return (
    <TimelineWorkspace
      birthDate={workspace.birthDate}
      birthDateAvailable={workspace.birthDateAvailable}
      chapters={workspace.chapters}
      defaultTimezone={workspace.defaultTimezone}
      firstTimes={workspace.firstTimes}
      loadError={workspace.loadError}
      ownerId={workspace.viewer.id}
      referenceDate={new Date().toISOString()}
      tagOptions={workspace.tagOptions}
    />
  );
}
