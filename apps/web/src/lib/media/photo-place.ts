export type PhotoPlaceDraft = {
  kind: "new" | "existing";
  attachmentId: string;
  placeId?: string;
  revision?: number;
  name?: string;
  latitude?: number;
  longitude?: number;
};
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
export function validPhotoPlace(value: unknown): value is PhotoPlaceDraft {
  if (!value || typeof value !== "object") return false;
  const p = value as PhotoPlaceDraft;
  if (typeof p.attachmentId !== "string" || !uuid.test(p.attachmentId))
    return false;
  if (p.kind === "existing")
    return (
      typeof p.placeId === "string" &&
      uuid.test(p.placeId) &&
      Number.isInteger(p.revision) &&
      p.revision! > 0 &&
      p.revision! < 1_000_000_000
    );
  return (
    p.kind === "new" &&
    typeof p.name === "string" &&
    p.name.trim().length > 0 &&
    p.name.trim().length <= 200 &&
    typeof p.latitude === "number" &&
    Number.isFinite(p.latitude) &&
    Math.abs(p.latitude) <= 90 &&
    typeof p.longitude === "number" &&
    Number.isFinite(p.longitude) &&
    Math.abs(p.longitude) <= 180
  );
}
