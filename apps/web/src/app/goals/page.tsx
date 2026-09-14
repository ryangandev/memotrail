import { GoalsWorkspace } from "@/components/goals-workspace";
import { getGoalsWorkspace } from "@/lib/data/goal-records";

export const dynamic = "force-dynamic";

export default async function GoalsPage({
  searchParams,
}: {
  searchParams: Promise<{ entry?: string | string[] }>;
}) {
  const workspace = await getGoalsWorkspace();
  if (!workspace) return null;

  const requestedEntry = (await searchParams).entry;
  const initialGoalId =
    typeof requestedEntry === "string" ? requestedEntry : null;

  return (
    <GoalsWorkspace
      collectionOptions={workspace.collectionOptions}
      goals={workspace.goals}
      initialGoalId={initialGoalId}
      linkOptions={workspace.linkOptions}
      loadError={workspace.loadError}
      ownerId={workspace.viewer.id}
      tagOptions={workspace.tagOptions}
    />
  );
}
