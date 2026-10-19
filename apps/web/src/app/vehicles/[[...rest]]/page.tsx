import { redirectRetiredRecord } from "@/lib/data/retired-routes";

export const dynamic = "force-dynamic";

// Vehicles are retired: a Vehicle is now a Chapter. An old Vehicle address
// opens that Chapter's Item page while it exists, and every other old address
// opens Timeline.
export default async function RetiredVehiclesPage({
  params,
}: {
  params: Promise<{ rest?: string[] }>;
}) {
  const { rest = [] } = await params;
  return redirectRetiredRecord(rest, "/timeline");
}
