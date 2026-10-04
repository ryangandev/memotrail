import { redirect } from "next/navigation";

// A First Time is an Entry, so its old address opens the Entry.
export default async function FirstTimeDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  redirect(`/items/${encodeURIComponent(id)}`);
}
