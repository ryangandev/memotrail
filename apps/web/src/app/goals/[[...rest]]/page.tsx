import { redirectRetiredRecord } from "@/lib/data/retired-routes";

export const dynamic = "force-dynamic";

// Someday is retired: an item is now an Entry tagged "someday". An old item
// address opens that Entry's Item page while it exists, and every other old
// address opens Library.
export default async function RetiredSomedayPage({
  params,
}: {
  params: Promise<{ rest?: string[] }>;
}) {
  const { rest = [] } = await params;
  return redirectRetiredRecord(rest, "/library");
}
