import { TimelineWorkspace } from "@/components/timeline-workspace";
import { getTimelineWorkspace } from "@/lib/data/timeline";
import { cookies } from "next/headers";
import {
  storedTimelineStyle,
  TIMELINE_STYLE_COOKIE_NAME,
} from "@/lib/timeline-style";

export const dynamic = "force-dynamic";

export default async function TimelinePage({
  searchParams,
}: {
  searchParams: Promise<{
    entry?: string | string[];
    new?: string | string[];
  }>;
}) {
  const parameters = await searchParams;
  const workspace = await getTimelineWorkspace();

  if (!workspace) {
    return null;
  }
  const timelineStyle = storedTimelineStyle(
    (await cookies()).get(TIMELINE_STYLE_COOKIE_NAME)?.value,
    workspace.viewer.id,
  );

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
      tagOptions={workspace.tagOptions}
      timelineStyle={timelineStyle}
      tracks={workspace.tracks}
      vehicles={workspace.vehicles}
    />
  );
}
