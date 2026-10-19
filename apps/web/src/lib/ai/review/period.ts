import type { SupabaseClient } from "@supabase/supabase-js";
import {
  occurrenceLabel,
  occurrenceSpanLabel,
  validTimezone,
  type OccurrencePrecision,
} from "@/lib/data/occurrence";

export type ReviewSubject =
  { scope: "chapter"; chapterId: string } | { scope: "year"; year: number };

export type PeriodEntry = {
  id: string;
  isSubject: boolean;
  title: string;
  body: string;
  revision: number;
  isFirstTime: boolean;
  /** The date as the person recorded it, with its precision, in English. */
  dateLabel: string;
  /** The days the Entry stands for; `windowEnd` is exclusive and null when open-ended. */
  windowStart: string | null;
  windowEnd: string | null;
  tags: string[];
};

export type PeriodChapter = { name: string; span: string };

export class PeriodError extends Error {
  constructor(public code: "review_not_eligible" | "period_unavailable") {
    super(code);
  }
}

type Row = Record<string, unknown>;

const text = (value: unknown) => (typeof value === "string" ? value : null);

function labelFor(row: Row, span: boolean) {
  const timezone = validTimezone(row.occurred_timezone)
    ? row.occurred_timezone
    : "UTC";
  const occurrence = {
    occurredAt: text(row.occurred_start),
    occurredEnd: text(row.occurred_end),
    occurredLabel: text(row.occurred_label),
    occurredTimezone: timezone,
    datePrecision: (text(row.date_precision) ??
      "unknown") as OccurrencePrecision,
  };
  return span ? occurrenceSpanLabel(occurrence) : occurrenceLabel(occurrence);
}

function parseEntry(row: Row): PeriodEntry | null {
  if (
    typeof row.entry_id !== "string" ||
    typeof row.body !== "string" ||
    !Number.isInteger(row.revision) ||
    typeof row.is_subject !== "boolean"
  )
    return null;
  return {
    id: row.entry_id,
    isSubject: row.is_subject,
    title: text(row.title)?.trim() ?? "",
    body: row.body,
    revision: row.revision as number,
    isFirstTime: row.is_first_time === true,
    dateLabel: labelFor(row, row.is_subject),
    windowStart: text(row.window_start),
    windowEnd: text(row.window_end),
    tags: Array.isArray(row.tag_names)
      ? row.tag_names.filter((tag): tag is string => typeof tag === "string")
      : [],
  };
}

/** Everything a review of this subject would read now, oldest first, a Chapter's own note first. */
export async function loadPeriod(
  client: SupabaseClient,
  subject: ReviewSubject,
): Promise<{ entries: PeriodEntry[]; chapters: PeriodChapter[] }> {
  const { data, error } = await client.rpc("review_period_entries", {
    p_scope: subject.scope,
    p_chapter_id: subject.scope === "chapter" ? subject.chapterId : null,
    p_year: subject.scope === "year" ? subject.year : null,
  });
  if (error) {
    throw new PeriodError(
      error.message === "review_subject_unavailable"
        ? "review_not_eligible"
        : "period_unavailable",
    );
  }
  if (!Array.isArray(data)) throw new PeriodError("period_unavailable");
  const entries = data.flatMap((row) => {
    const entry = isRow(row) ? parseEntry(row) : null;
    return entry ? [entry] : [];
  });

  let chapters: PeriodChapter[] = [];
  if (subject.scope === "year") {
    const result = await client.rpc("review_period_chapters", {
      p_year: subject.year,
    });
    if (result.error || !Array.isArray(result.data))
      throw new PeriodError("period_unavailable");
    chapters = result.data.flatMap((row) =>
      isRow(row) && typeof row.entry_id === "string"
        ? [
            {
              name: text(row.title)?.trim() || "Untitled Chapter",
              span: labelFor(row, true),
            },
          ]
        : [],
    );
  }
  return { entries, chapters };
}

function isRow(value: unknown): value is Row {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

const MONTHS = new Intl.DateTimeFormat("en-US", {
  month: "long",
  year: "numeric",
  timeZone: "UTC",
});

/** "January 2025 - March 2025", or a single month, from the first and last day a set of Entries stands for. */
export function monthSpanLabel(
  entries: readonly Pick<PeriodEntry, "windowStart" | "windowEnd">[],
) {
  const starts = entries.flatMap((entry) =>
    entry.windowStart ? [entry.windowStart] : [],
  );
  if (starts.length === 0) return "Date unknown";
  const first = [...starts].sort()[0];
  const ends = entries
    .map((entry) => entry.windowEnd ?? entry.windowStart!)
    .sort();
  const lastExclusive = ends[ends.length - 1];
  const last = new Date(`${lastExclusive}T00:00:00Z`);
  last.setUTCDate(last.getUTCDate() - 1);
  const from = MONTHS.format(new Date(`${first}T00:00:00Z`));
  const to = MONTHS.format(
    last < new Date(`${first}T00:00:00Z`)
      ? new Date(`${first}T00:00:00Z`)
      : last,
  );
  return from === to ? from : `${from} - ${to}`;
}
