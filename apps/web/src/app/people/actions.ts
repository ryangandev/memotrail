"use server";

import { revalidatePath } from "next/cache";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { parsePersonInput, type PersonInput } from "@/lib/data/person";

export async function savePerson(input: PersonInput): Promise<string | null> {
  const parsed = parsePersonInput(input);
  if (!parsed)
    return "Add a name of up to 200 characters, a relationship up to 200, notes up to 10,000, and at most 100 Entry links.";
  const context = await getAuthenticatedContext();
  if (!context) return "Sign in again to save this Person.";
  const { data, error } = await context.client.rpc("save_person", {
    p_person_id: parsed.id,
    p_expected_revision: parsed.revision,
    p_name: parsed.name,
    p_relationship_label: parsed.relationshipLabel,
    p_notes: parsed.notes,
    p_related_entry_ids: parsed.entryIds,
  });
  if (error)
    return "Could not save this Person. Check the Entry links and try again.";
  if (!Array.isArray(data) || !data.length)
    return "This Person changed on another device. Refresh before editing again.";
  refresh();
  return null;
}

export async function trashPerson(
  id: string,
  revision: number,
): Promise<string | null> {
  if (
    !parsePersonInput({
      id,
      revision,
      name: "Check",
      relationshipLabel: "",
      notes: "",
      entryIds: [],
    })
  )
    return "Invalid Person version.";
  const context = await getAuthenticatedContext();
  if (!context) return "Sign in again to continue.";
  const { data, error } = await context.client.rpc("trash_person", {
    p_person_id: id,
    p_expected_revision: revision,
  });
  if (error || !Array.isArray(data) || !data.length)
    return "This Person changed or still has Entry links. Unlink and save before moving to Trash.";
  refresh();
  return null;
}

function refresh() {
  for (const path of ["/people", "/library", "/trash", "/search"])
    revalidatePath(path);
}
