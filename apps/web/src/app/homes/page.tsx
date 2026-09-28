import { HomesWorkspace } from "@/components/homes-workspace";
import { getCaptureExtractionSource } from "@/lib/data/capture-extraction";
import { getHomesWorkspace } from "@/lib/data/home-records";
import { redirect } from "next/navigation";

export const dynamic = "force-dynamic";

export default async function HomesPage({
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
    redirect(`/homes/${requestedEntry}`);
  const [workspace, sourceCapture] = await Promise.all([
    getHomesWorkspace(),
    getCaptureExtractionSource(
      typeof requestedSource === "string" ? requestedSource : null,
    ),
  ]);

  if (!workspace) {
    return null;
  }

  const initialHomeId =
    typeof requestedEntry === "string" ? requestedEntry : null;

  return (
    <HomesWorkspace
      collectionOptions={workspace.collectionOptions}
      homes={workspace.homes}
      initialHomeId={initialHomeId}
      loadError={workspace.loadError}
      ownerId={workspace.viewer.id}
      sourceCapture={sourceCapture}
      tagOptions={workspace.tagOptions}
    />
  );
}
