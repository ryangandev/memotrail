export type BirthDateResult =
  | { birthDate: string | null; success: true }
  | { message: string; success: false };

export type StoredBirthDate = {
  available: boolean;
  birthDate: string | null;
};

const earliestBirthDate = "1800-01-01";

export function parseBirthDate(
  value: string,
  today = new Date().toISOString().slice(0, 10),
): BirthDateResult {
  const birthDate = value.trim();

  if (!birthDate) return { birthDate: null, success: true };

  if (!validDateOnly(birthDate)) {
    return { message: "Choose a complete birth date.", success: false };
  }

  if (birthDate < earliestBirthDate || birthDate > today) {
    return {
      message: "Birth date must be between 1800 and today.",
      success: false,
    };
  }

  return { birthDate, success: true };
}

export function validStoredBirthDate(value: unknown): value is string {
  return typeof value === "string" && validDateOnly(value);
}

export function storedBirthDate(value: unknown): StoredBirthDate {
  if (typeof value !== "object" || value === null || !("birth_date" in value)) {
    return { available: false, birthDate: null };
  }

  return {
    available: true,
    birthDate: validStoredBirthDate(value.birth_date) ? value.birth_date : null,
  };
}

function validDateOnly(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;

  const [year, month, day] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));

  return (
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day
  );
}
