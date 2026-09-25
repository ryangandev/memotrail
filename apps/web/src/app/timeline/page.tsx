import { TimelineWorkspace } from "@/components/timeline-workspace";
import { getTimelineWorkspace } from "@/lib/data/timeline";

export const dynamic = "force-dynamic";

export default async function TimelinePage({
  searchParams,
}: {
  searchParams: Promise<{ entry?: string | string[] }>;
}) {
  const parameters = await searchParams;
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
      initialEntryId={typeof parameters.entry === "string" ? parameters.entry : null}
      loadError={workspace.loadError}
      ownerId={workspace.viewer.id}
      referenceDate={new Date().toISOString()}
      tagOptions={workspace.tagOptions}
      tracks={workspace.tracks}
      vehicles={workspace.vehicles}
    />
  );
}
