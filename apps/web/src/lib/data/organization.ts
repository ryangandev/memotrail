export type OrganizationKind = "collection" | "tag";
export type OrganizationItem = {
  id: string;
  name: string;
  system_key: string | null;
  sort_order: number;
  revision: number;
  entry_count: number;
  total_count: number;
};
export type OrganizationInput = {
  kind: OrganizationKind;
  id: string | null;
  revision: number | null;
  name: string;
  order: number;
};
export function validOrganizationInput(value: OrganizationInput) {
  return (
    value &&
    (value.kind === "collection" || value.kind === "tag") &&
    typeof value.name === "string" &&
    value.name.trim().length > 0 &&
    [...value.name.trim()].length <= 80 &&
    Number.isInteger(value.order) &&
    Math.abs(value.order) <= 1000000 &&
    (value.kind !== "tag" || value.order === 0) &&
    (value.id === null
      ? value.revision === null
      : typeof value.id === "string" &&
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
          value.id,
        ) &&
        Number.isSafeInteger(value.revision) &&
        Number(value.revision) > 0)
  );
}
