import { HomesWorkspace } from "@/components/homes-workspace";
import { getHomesWorkspace } from "@/lib/data/home-records";

export const dynamic = "force-dynamic";

export default async function HomesPage({
  searchParams,
}: {
  searchParams: Promise<{ entry?: string | string[] }>;
}) {
  const workspace = await getHomesWorkspace();

  if (!workspace) {
    return null;
  }

  const requestedEntry = (await searchParams).entry;
  const initialHomeId =
    typeof requestedEntry === "string" ? requestedEntry : null;

  return (
    <HomesWorkspace
      collectionOptions={workspace.collectionOptions}
      homes={workspace.homes}
      initialHomeId={initialHomeId}
      loadError={workspace.loadError}
      ownerId={workspace.viewer.id}
      placeOptions={workspace.placeOptions}
      tagOptions={workspace.tagOptions}
    />
  );
}
