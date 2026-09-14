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
      collectionOptions={workspace.collectionOptions}
      defaultTimezone={workspace.defaultTimezone}
      firstTimes={workspace.firstTimes}
      homes={workspace.homes}
      loadError={workspace.loadError}
      ownerId={workspace.viewer.id}
      placeOptions={workspace.placeOptions}
      referenceDate={new Date().toISOString()}
      tagOptions={workspace.tagOptions}
      tracks={workspace.tracks}
      vehicles={workspace.vehicles}
    />
  );
}
