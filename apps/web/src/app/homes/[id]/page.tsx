import { FocusedDetailUnavailable } from "@/components/focused-detail-unavailable";
import { FocusedRecordDetail } from "@/components/focused-record-detail";
import { getHomesWorkspace } from "@/lib/data/home-records";
import { isFirstTimeUuid } from "@/lib/data/first-time-input";

export const dynamic = "force-dynamic";
export default async function HomeDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  if (!isFirstTimeUuid(id))
    return <FocusedDetailUnavailable label="Home" back="/homes" />;
  const workspace = await getHomesWorkspace(id);
  if (!workspace) return null;
  const record = workspace.homes.find((home) => home.id === id);
  if (!record) return <FocusedDetailUnavailable label="Home" back="/homes" />;
  return (
    <FocusedRecordDetail
      kind="home"
      record={record}
      tagOptions={workspace.tagOptions}
      ownerId={workspace.viewer.id}
    />
  );
}
