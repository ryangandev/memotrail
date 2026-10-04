import { FocusedDetailUnavailable } from "@/components/focused-detail-unavailable";
import { FocusedRecordDetail } from "@/components/focused-record-detail";
import { getFirstTimesWorkspace } from "@/lib/data/first-times";
import { isFirstTimeUuid } from "@/lib/data/first-time-input";

export const dynamic = "force-dynamic";
export default async function FirstTimeDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  if (!isFirstTimeUuid(id))
    return <FocusedDetailUnavailable label="First Time" back="/first-times" />;
  const workspace = await getFirstTimesWorkspace(id);
  if (!workspace) return null;
  const record = workspace.entries.find((entry) => entry.id === id);
  if (!record)
    return <FocusedDetailUnavailable label="First Time" back="/first-times" />;
  return (
    <FocusedRecordDetail
      kind="first-time"
      record={record}
      tagOptions={workspace.tagOptions}
      ownerId={workspace.viewer.id}
    />
  );
}
