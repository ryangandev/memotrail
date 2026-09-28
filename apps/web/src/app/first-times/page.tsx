import { FirstTimesWorkspace } from "@/components/first-times-workspace";
import { getFirstTimesWorkspace } from "@/lib/data/first-times";
import { redirect } from "next/navigation";

export const dynamic = "force-dynamic";

export default async function FirstTimesPage({
  searchParams,
}: {
  searchParams: Promise<{ entry?: string | string[] }>;
}) {
  const parameters = await searchParams;
  if (typeof parameters.entry === "string")
    redirect(`/first-times/${parameters.entry}`);
  const workspace = await getFirstTimesWorkspace();

  if (!workspace) {
    return null;
  }

  return (
    <FirstTimesWorkspace
      collectionOptions={workspace.collectionOptions}
      entries={workspace.entries}
      initialEntryId={
        typeof parameters.entry === "string" ? parameters.entry : null
      }
      loadError={workspace.loadError}
      ownerId={workspace.viewer.id}
      tagOptions={workspace.tagOptions}
    />
  );
}
