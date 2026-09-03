import { isLocalDate } from "./habit-input";

export type RawHabitsParams = Record<string, string | string[] | undefined>;

export function parseHabitsRequest(
  value: RawHabitsParams,
  fallbackDate: string,
) {
  const rawDate = firstValue(value.date);
  const referenceDate =
    rawDate && isLocalDate(rawDate) ? rawDate : fallbackDate;
  const rawYear = firstValue(value.year);
  const parsedYear = rawYear
    ? Number(rawYear)
    : Number(referenceDate.slice(0, 4));
  const selectedYear =
    Number.isSafeInteger(parsedYear) && parsedYear >= 1900 && parsedYear <= 2200
      ? parsedYear
      : Number(referenceDate.slice(0, 4));
  const habitId = firstValue(value.habit)?.trim() || null;

  return {
    hasExplicitDate: Boolean(rawDate && isLocalDate(rawDate)),
    habitId,
    referenceDate,
    selectedYear,
  };
}

export function habitsHref({
  date,
  habitId,
  year,
}: {
  date?: string;
  habitId?: string | null;
  year?: number;
}) {
  const params = new URLSearchParams();

  if (date) {
    params.set("date", date);
  }
  if (habitId) {
    params.set("habit", habitId);
  }
  if (year) {
    params.set("year", String(year));
  }

  const query = params.toString();
  return query ? `/habits?${query}` : "/habits";
}

function firstValue(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}
