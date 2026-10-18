import { FocusedDetailUnavailable } from "@/components/focused-detail-unavailable";
import { FocusedRecordDetail } from "@/components/focused-record-detail";
import { getGoalsWorkspace } from "@/lib/data/goal-records";
import { isEntryUuid } from "@/lib/data/entry-photo-input";

export const dynamic = "force-dynamic";
export default async function GoalDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  if (!isEntryUuid(id))
    return (
      <FocusedDetailUnavailable
        label="Someday item"
        back="/goals"
        backLabel="Someday"
      />
    );
  const workspace = await getGoalsWorkspace(id);
  if (!workspace) return null;
  const record = workspace.goals.find((goal) => goal.id === id);
  if (!record)
    return (
      <FocusedDetailUnavailable
        label="Someday item"
        back="/goals"
        backLabel="Someday"
      />
    );
  return (
    <FocusedRecordDetail
      kind="goal"
      record={record}
      defaultTimezone={workspace.defaultTimezone}
      tagOptions={workspace.tagOptions}
      ownerId={workspace.viewer.id}
    />
  );
}
