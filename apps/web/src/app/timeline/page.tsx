import { TimelineWorkspace } from "@/components/timeline-workspace";
import { getTimelineWorkspace } from "@/lib/data/timeline";
import { timelineIdeaReturnPath } from "./ideas/_shared/navigation";

export const dynamic = "force-dynamic";

export default async function TimelinePage({
  searchParams,
}: {
  searchParams: Promise<{
    entry?: string | string[];
    new?: string | string[];
    returnTo?: string | string[];
  }>;
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
      initialEntryId={
        typeof parameters.entry === "string" ? parameters.entry : null
      }
      initialCreate={parameters.new === "1"}
      loadError={workspace.loadError}
      ownerId={workspace.viewer.id}
      referenceDate={new Date().toISOString()}
      returnTo={timelineIdeaReturnPath(parameters.returnTo)}
      tagOptions={workspace.tagOptions}
      tracks={workspace.tracks}
      vehicles={workspace.vehicles}
    />
  );
}
