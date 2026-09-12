export type TrackSetting = {
  id: string;
  name: string;
  system_key: string | null;
  sort_order: number;
  is_hidden: boolean;
  revision: number;
  entry_count: number;
  total_count: number;
};
export type TrackInput = {
  id: string | null;
  revision: number | null;
  name: string;
  order: number;
  hidden: boolean;
};
export function validTrackInput(input: TrackInput) {
  return (
    typeof input.name === "string" &&
    input.name.trim().length > 0 &&
    [...input.name.trim()].length <= 100 &&
    Number.isInteger(input.order) &&
    Math.abs(input.order) <= 1000000 &&
    typeof input.hidden === "boolean" &&
    (input.id === null
      ? input.revision === null
      : typeof input.id === "string" &&
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
          input.id,
        ) &&
        Number.isSafeInteger(input.revision) &&
        Number(input.revision) > 0)
  );
}
