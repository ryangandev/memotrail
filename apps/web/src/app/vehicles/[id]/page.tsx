import { FocusedDetailUnavailable } from "@/components/focused-detail-unavailable";
import { FocusedRecordDetail } from "@/components/focused-record-detail";
import { getVehiclesWorkspace } from "@/lib/data/vehicle-records";
import { isFirstTimeUuid } from "@/lib/data/first-time-input";

export const dynamic = "force-dynamic";
export default async function VehicleDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  if (!isFirstTimeUuid(id))
    return <FocusedDetailUnavailable label="Vehicle" back="/vehicles" />;
  const workspace = await getVehiclesWorkspace(id);
  if (!workspace) return null;
  const record = workspace.vehicles.find((vehicle) => vehicle.id === id);
  if (!record)
    return <FocusedDetailUnavailable label="Vehicle" back="/vehicles" />;
  return (
    <FocusedRecordDetail
      kind="vehicle"
      record={record}
      tagOptions={workspace.tagOptions}
      ownerId={workspace.viewer.id}
    />
  );
}
