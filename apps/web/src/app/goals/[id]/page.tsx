import { FocusedDetailUnavailable } from "@/components/focused-detail-unavailable";
import { FocusedRecordDetail } from "@/components/focused-record-detail";
import { getGoalsWorkspace } from "@/lib/data/goal-records";
import { isFirstTimeUuid } from "@/lib/data/first-time-input";

export const dynamic = "force-dynamic";
export default async function GoalDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  if (!isFirstTimeUuid(id))
    return <FocusedDetailUnavailable label="Goal" back="/goals" />;
  const workspace = await getGoalsWorkspace(id);
  if (!workspace) return null;
  const record = workspace.goals.find((goal) => goal.id === id);
  if (!record) return <FocusedDetailUnavailable label="Goal" back="/goals" />;
  return (
    <FocusedRecordDetail
      kind="goal"
      record={record}
      tagOptions={workspace.tagOptions}
      ownerId={workspace.viewer.id}
      linkOptions={workspace.linkOptions}
    />
  );
}
