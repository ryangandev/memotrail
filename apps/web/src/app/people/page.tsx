import { PeopleWorkspace } from "@/components/people-workspace";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import type { Person, PersonEntry } from "@/lib/data/person";
import { isFirstTimeUuid } from "@/lib/data/first-time-input";

export const dynamic = "force-dynamic";

export default async function PeoplePage({
  searchParams,
}: {
  searchParams: Promise<{ page?: string; person?: string }>;
}) {
  const context = await getAuthenticatedContext();
  if (!context) return null;
  const parameters = await searchParams;
  const focused = parameters.person;
  const raw = Number(parameters.page ?? 1);
  const page =
    !focused && Number.isInteger(raw) && raw > 0 && raw <= 101 ? raw : 1;
  const [people, entries] = await Promise.all([
    focused
      ? isFirstTimeUuid(focused)
        ? context.client.rpc("person_record", { p_person_id: focused })
        : Promise.resolve({ data: [], error: null })
      : context.client.rpc("people_workspace", {
          p_limit: 100,
          p_offset: (page - 1) * 100,
        }),
    context.client
      .from("entries")
      .select("id,title,body,item_kind,item_subtype")
      .eq("owner_id", context.userId)
      .is("deleted_at", null)
      .order("updated_at", { ascending: false })
      .limit(200),
  ]);
  return (
    <PeopleWorkspace
      focused={Boolean(focused)}
      people={(people.data ?? []) as Person[]}
      entries={(entries.data ?? []) as PersonEntry[]}
      page={page}
      error={
        focused && !people.error && people.data?.length === 0
          ? "This Person is unavailable or in Trash."
          : people.error || entries.error
            ? "Could not load People and Entry choices. Refresh to try again."
            : null
      }
    />
  );
}
