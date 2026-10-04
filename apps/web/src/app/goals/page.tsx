import { GoalsWorkspace } from "@/components/goals-workspace";
import { getGoalsWorkspace } from "@/lib/data/goal-records";
import { redirect } from "next/navigation";

export const dynamic = "force-dynamic";

export default async function GoalsPage({
  searchParams,
}: {
  searchParams: Promise<{ entry?: string | string[] }>;
}) {
  const requestedEntry = (await searchParams).entry;
  if (typeof requestedEntry === "string") redirect(`/goals/${requestedEntry}`);
  const workspace = await getGoalsWorkspace();
  if (!workspace) return null;

  return (
    <GoalsWorkspace
      goals={workspace.goals}
      loadError={workspace.loadError}
      ownerId={workspace.viewer.id}
      tagOptions={workspace.tagOptions}
    />
  );
}
