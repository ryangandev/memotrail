import type { InboxEntry } from "./inbox";

export type CaptureExtractionSource = InboxEntry;

export type CaptureExtractionReference = {
  id: string;
  revision: number;
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function parseCaptureExtractionReference(
  value: unknown,
): CaptureExtractionReference | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const reference = value as Record<string, unknown>;
  return typeof reference.id === "string" &&
    uuidPattern.test(reference.id) &&
    typeof reference.revision === "number" &&
    Number.isSafeInteger(reference.revision) &&
    reference.revision >= 1
    ? { id: reference.id, revision: reference.revision }
    : null;
}

/** A Capture hands off only the create call. Once its record exists, Save is an ordinary update. */
export function pendingCaptureReference(
  source: CaptureExtractionReference | null,
  recordId: string | null,
): CaptureExtractionReference | null {
  return source && recordId === null
    ? { id: source.id, revision: source.revision }
    : null;
}
