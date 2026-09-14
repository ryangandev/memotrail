import { validTimezone } from "./occurrence";

export type BirthDateResult =
  | { birthDate: string | null; success: true }
  | { message: string; success: false };

export type StoredBirthDate = {
  available: boolean;
  birthDate: string | null;
};

export type ProfileTimezoneResult =
  { success: true; timezone: string } | { message: string; success: false };

export type StoredProfileTimezone = {
  available: boolean;
  timezone: string;
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

export function parseProfileTimezone(value: string): ProfileTimezoneResult {
  const timezone = value.trim();

  return validTimezone(timezone)
    ? { success: true, timezone }
    : {
        message: "Choose a valid time zone.",
        success: false,
      };
}

export function storedProfileTimezone(value: unknown): StoredProfileTimezone {
  if (typeof value !== "object" || value === null || !("timezone" in value)) {
    return { available: false, timezone: "UTC" };
  }

  return {
    available: true,
    timezone: validTimezone(value.timezone) ? value.timezone : "UTC",
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
