import { TimelineWorkspace } from "@/components/timeline-workspace";
import { getTimelineWorkspace } from "@/lib/data/timeline";
import { cookies } from "next/headers";
import {
  storedTimelineStyle,
  TIMELINE_STYLE_COOKIE_NAME,
} from "@/lib/timeline-style";

export const dynamic = "force-dynamic";

export default async function TimelinePage() {
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
      defaultTimezone={workspace.defaultTimezone}
      lanes={workspace.lanes}
      loadError={workspace.loadError}
      ownerId={workspace.viewer.id}
      referenceDate={new Date().toISOString()}
      tagOptions={workspace.tagOptions}
      timelineStyle={timelineStyle}
    />
  );
}
