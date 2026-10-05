import { FirstTimesWorkspace } from "@/components/first-times-workspace";
import { getFirstTimesWorkspace } from "@/lib/data/first-times";

export const dynamic = "force-dynamic";

export default async function FirstTimesPage() {
  const workspace = await getFirstTimesWorkspace();

  if (!workspace) {
    return null;
  }

  return (
    <FirstTimesWorkspace
      defaultTimezone={workspace.defaultTimezone}
      entries={workspace.entries}
      loadError={workspace.loadError}
      ownerId={workspace.viewer.id}
      tagOptions={workspace.tagOptions}
    />
  );
}
