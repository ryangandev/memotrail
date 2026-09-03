export type CaptureDateResult =
  { occurredAt: string; success: true } | { message: string; success: false };

export function parseCaptureDate(
  localValue: string | null,
  fallback: Date,
): CaptureDateResult {
  const date = localValue ? new Date(localValue) : fallback;

  if (Number.isNaN(date.getTime())) {
    return {
      message: "Choose a valid relevant date and time.",
      success: false,
    };
  }

  return { occurredAt: date.toISOString(), success: true };
}

export function localCaptureDateValue(date: Date) {
  const localDate = new Date(
    date.getTime() - date.getTimezoneOffset() * 60_000,
  );
  return localDate.toISOString().slice(0, 16);
}

export function captureDateLabel(localValue: string) {
  return new Intl.DateTimeFormat("en-US", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(localValue));
}
