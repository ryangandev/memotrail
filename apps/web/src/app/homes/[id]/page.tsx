import { FocusedDetailUnavailable } from "@/components/focused-detail-unavailable";
import { FocusedRecordDetail } from "@/components/focused-record-detail";
import { getHomesWorkspace } from "@/lib/data/home-records";
import { isEntryUuid } from "@/lib/data/entry-photo-input";

export const dynamic = "force-dynamic";
export default async function HomeDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  if (!isEntryUuid(id))
    return (
      <FocusedDetailUnavailable label="Home" back="/homes" backLabel="Homes" />
    );
  const workspace = await getHomesWorkspace(id);
  if (!workspace) return null;
  const record = workspace.homes.find((home) => home.id === id);
  if (!record)
    return (
      <FocusedDetailUnavailable label="Home" back="/homes" backLabel="Homes" />
    );
  return (
    <FocusedRecordDetail
      kind="home"
      record={record}
      defaultTimezone={workspace.defaultTimezone}
      tagOptions={workspace.tagOptions}
      ownerId={workspace.viewer.id}
    />
  );
}
