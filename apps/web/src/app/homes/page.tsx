import { HomesWorkspace } from "@/components/homes-workspace";
import { getHomesWorkspace } from "@/lib/data/home-records";
import { redirect } from "next/navigation";

export const dynamic = "force-dynamic";

export default async function HomesPage({
  searchParams,
}: {
  searchParams: Promise<{ entry?: string | string[] }>;
}) {
  const requestedEntry = (await searchParams).entry;
  if (typeof requestedEntry === "string") redirect(`/homes/${requestedEntry}`);
  const workspace = await getHomesWorkspace();

  if (!workspace) {
    return null;
  }

  return (
    <HomesWorkspace
      homes={workspace.homes}
      loadError={workspace.loadError}
      ownerId={workspace.viewer.id}
      defaultTimezone={workspace.defaultTimezone}
      tagOptions={workspace.tagOptions}
    />
  );
}
