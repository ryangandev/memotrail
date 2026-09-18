export type PlaceRecord = {
  address: string | null;
  city: string | null;
  country: string | null;
  createdAt: string;
  id: string;
  latitude: number | null;
  longitude: number | null;
  name: string;
  notes: string | null;
  region: string | null;
  revision: number;
  totalCount: number;
  updatedAt: string;
};

export function parsePlaceRows(value: unknown): PlaceRecord[] | null {
  if (!Array.isArray(value)) return null;
  const places: PlaceRecord[] = [];
  for (const item of value) {
    const place = parsePlaceRow(item);
    if (!place) return null;
    places.push(place);
  }
  return places;
}

export function placeLocationLabel(place: PlaceRecord) {
  const locality = [place.city, place.region, place.country].filter(Boolean);
  if (place.address && locality.length > 0) {
    return `${place.address} · ${locality.join(", ")}`;
  }
  return place.address || locality.join(", ") || "Location details not added";
}

function parsePlaceRow(value: unknown): PlaceRecord | null {
  if (
    !isRecord(value) ||
    typeof value.place_id !== "string" ||
    typeof value.name !== "string" ||
    !nullableString(value.address) ||
    !nullableString(value.city) ||
    !nullableString(value.region) ||
    !nullableString(value.country) ||
    !nullableNumber(value.latitude) ||
    !nullableNumber(value.longitude) ||
    !nullableString(value.notes) ||
    typeof value.revision !== "number" ||
    typeof value.created_at !== "string" ||
    typeof value.updated_at !== "string" ||
    !countLike(value.total_count)
  ) {
    return null;
  }

  return {
    address: value.address,
    city: value.city,
    country: value.country,
    createdAt: value.created_at,
    id: value.place_id,
    latitude: value.latitude,
    longitude: value.longitude,
    name: value.name,
    notes: value.notes,
    region: value.region,
    revision: value.revision,
    totalCount: safeCount(value.total_count),
    updatedAt: value.updated_at,
  };
}

function nullableNumber(value: unknown): value is number | null {
  return (
    value === null || (typeof value === "number" && Number.isFinite(value))
  );
}

function nullableString(value: unknown) {
  return value === null || typeof value === "string";
}

function countLike(value: unknown): value is number | string {
  return typeof value === "number" || typeof value === "string";
}

function safeCount(value: number | string) {
  const count = typeof value === "number" ? value : Number(value);
  return Number.isSafeInteger(count) && count >= 0 ? count : 0;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
