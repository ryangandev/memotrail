import { FocusedDetailUnavailable } from "@/components/focused-detail-unavailable";
import { FocusedRecordDetail } from "@/components/focused-record-detail";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { isFirstTimeUuid } from "@/lib/data/first-time-input";
import type { Person, PersonEntry } from "@/lib/data/person";

export const dynamic = "force-dynamic";
export default async function PersonDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const context = await getAuthenticatedContext();
  if (!context) return null;
  if (!isFirstTimeUuid(id))
    return <FocusedDetailUnavailable label="Person" back="/people" />;
  const [people, entries] = await Promise.all([
    context.client.rpc("person_record", { p_person_id: id }),
    context.client
      .from("entries")
      .select("id,title,body,item_kind,item_subtype")
      .eq("owner_id", context.userId)
      .is("deleted_at", null)
      .order("updated_at", { ascending: false })
      .limit(200),
  ]);
  const record = (people.data as Person[] | null)?.[0];
  if (people.error || !record)
    return <FocusedDetailUnavailable label="Person" back="/people" />;
  return (
    <FocusedRecordDetail
      kind="person"
      record={record}
      entries={(entries.data ?? []) as PersonEntry[]}
      tagOptions={[]}
      ownerId={context.viewer.id}
    />
  );
}
