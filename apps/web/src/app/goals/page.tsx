import { GoalsWorkspace } from "@/components/goals-workspace";
import { getCaptureExtractionSource } from "@/lib/data/capture-extraction";
import { getGoalsWorkspace } from "@/lib/data/goal-records";
import { redirect } from "next/navigation";

export const dynamic = "force-dynamic";

export default async function GoalsPage({
  searchParams,
}: {
  searchParams: Promise<{
    entry?: string | string[];
    source?: string | string[];
  }>;
}) {
  const params = await searchParams;
  const requestedEntry = params.entry;
  const requestedSource = params.source;
  if (typeof requestedEntry === "string" && !requestedSource)
    redirect(`/goals/${requestedEntry}`);
  const [workspace, sourceCapture] = await Promise.all([
    getGoalsWorkspace(),
    getCaptureExtractionSource(
      typeof requestedSource === "string" ? requestedSource : null,
    ),
  ]);
  if (!workspace) return null;

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
      sourceCapture={sourceCapture}
      tagOptions={workspace.tagOptions}
    />
  );
}
