import { AuthGate } from "@/components/auth-gate";
import { WorkspaceShell } from "@/components/workspace-shell";
import { PeopleWorkspace } from "@/components/people-workspace";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { getSupabasePublicConfig } from "@/lib/supabase/config";
import type { Person, PersonEntry } from "@/lib/data/person";

export const dynamic = "force-dynamic";

export default async function PeoplePage({
  searchParams,
}: {
  searchParams: Promise<{ page?: string }>;
}) {
  if (!getSupabasePublicConfig()) return <AuthGate configured={false} />;
  const context = await getAuthenticatedContext();
  if (!context) return <AuthGate configured />;
  const raw = Number((await searchParams).page ?? 1);
  const page = Number.isInteger(raw) && raw > 0 && raw <= 101 ? raw : 1;
  const [people, entries] = await Promise.all([
    context.client.rpc("people_workspace", {
      p_limit: 100,
      p_offset: (page - 1) * 100,
    }),
    context.client
      .from("entries")
      .select("id,title,body,entry_type")
      .eq("owner_id", context.userId)
      .is("deleted_at", null)
      .order("updated_at", { ascending: false })
      .limit(200),
  ]);
  return (
    <WorkspaceShell activeDestination="people" viewer={context.viewer}>
      <PeopleWorkspace
        people={(people.data ?? []) as Person[]}
        entries={(entries.data ?? []) as PersonEntry[]}
        page={page}
        error={
          people.error || entries.error
            ? "Could not load People and Entry choices. Refresh to try again."
            : null
        }
      />
    </WorkspaceShell>
  );
}
