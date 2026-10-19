import { redirectRetiredRecord } from "@/lib/data/retired-routes";

export const dynamic = "force-dynamic";

// Homes are retired: a Home is now a Chapter. An old Home address opens that
// Chapter's Item page while it exists, and every other old address opens
// Timeline.
export default async function RetiredHomesPage({
  params,
}: {
  params: Promise<{ rest?: string[] }>;
}) {
  const { rest = [] } = await params;
  return redirectRetiredRecord(rest, "/timeline");
}
