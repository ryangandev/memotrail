/** A photo's GPS position the editor adds as a Location when the Entry saves. */
export type PhotoLocationDraft = {
  attachmentId: string;
  latitude: number;
  longitude: number;
};

const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;

export function validPhotoLocation(
  value: unknown,
): value is PhotoLocationDraft {
  if (!value || typeof value !== "object") return false;
  const draft = value as Partial<PhotoLocationDraft>;
  return (
    typeof draft.attachmentId === "string" &&
    uuid.test(draft.attachmentId) &&
    typeof draft.latitude === "number" &&
    Number.isFinite(draft.latitude) &&
    Math.abs(draft.latitude) <= 90 &&
    typeof draft.longitude === "number" &&
    Number.isFinite(draft.longitude) &&
    Math.abs(draft.longitude) <= 180
  );
}
