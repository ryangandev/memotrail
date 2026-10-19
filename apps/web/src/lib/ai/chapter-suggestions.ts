import type { SupabaseClient } from "@supabase/supabase-js";
import { REVIEW_MODEL } from "./contracts";
import { AIError, requestAI } from "./server";
import { REVIEW_DISCLOSURE_VERSION } from "./review-disclosure";
import { parseModelJson, quotationsHold } from "./review/grounding";
import { codePointLength } from "./review/passages";
import { monthSpanLabel } from "./review/period";
import {
  buildChapterSuggestionInput,
  chapterSuggestionSchema,
  chapterSuggestionSystemPrompt,
  type SuggestionPromptEntry,
} from "./review/prompts";
import {
  occurrenceLabel,
  occurrenceSpanLabel,
  validTimezone,
  type OccurrencePrecision,
} from "@/lib/data/occurrence";

/** The most Entries a run reads, the fewest worth asking about, and how much of the input is allowed. */
export const SUGGESTION_MAX_BYTES = 120_000;
export const SUGGESTION_MIN_ENTRIES = 12;
const LOOKBACK_MONTHS = 18;
const EXCERPT_CODE_POINTS = 200;
const MAX_PENDING = 3;

export type SuggestionEntry = {
  /** The short ID the model sees, "S1" for the newest. */
  ref: string;
  id: string;
  title: string;
  excerpt: string;
  tags: string[];
  dateLabel: string;
  windowStart: string;
  /** Exclusive. */
  windowEnd: string;
};

export type KnownWindow = { windowStart: string; windowEnd: string | null };
export type ExistingChapter = KnownWindow & { title: string };

export type ValidSuggestion = {
  name: string;
  rationale: string;
  sourceEntryIds: string[];
  startDate: string;
  startPrecision: "day" | "month";
  endDate: string | null;
  endPrecision: "day" | "month" | null;
  windowStart: string;
  windowEnd: string | null;
};

type Row = Record<string, unknown>;
const isRow = (value: unknown): value is Row =>
  typeof value === "object" && value !== null && !Array.isArray(value);
const text = (value: unknown) => (typeof value === "string" ? value : null);

const DAY = 86_400_000;
const dayNumber = (date: string) => Math.floor(Date.parse(`${date}T00:00:00Z`) / DAY);
function addDays(date: string, days: number) {
  return new Date(Date.parse(`${date}T00:00:00Z`) + days * DAY).toISOString().slice(0, 10);
}
function addMonths(date: string, months: number) {
  const value = new Date(`${date}T00:00:00Z`);
  value.setUTCDate(1);
  value.setUTCMonth(value.getUTCMonth() + months);
  return value.toISOString().slice(0, 10);
}

/**
 * How much two stretches of days overlap: the overlap over the union. A stretch without an end
 * runs through the day after `today`. This mirrors the database function `window_iou`.
 */
export function windowIou(left: KnownWindow, right: KnownWindow, today: string) {
  const leftStart = dayNumber(left.windowStart);
  const rightStart = dayNumber(right.windowStart);
  const tomorrow = dayNumber(today) + 1;
  const leftEnd = Math.max(left.windowEnd ? dayNumber(left.windowEnd) : tomorrow, leftStart + 1);
  const rightEnd = Math.max(right.windowEnd ? dayNumber(right.windowEnd) : tomorrow, rightStart + 1);
  const overlap = Math.max(0, Math.min(leftEnd, rightEnd) - Math.max(leftStart, rightStart));
  const total = leftEnd - leftStart + (rightEnd - rightStart) - overlap;
  return total <= 0 ? 0 : overlap / total;
}

function parsePoint(value: unknown): { date: string; precision: "day" | "month" } | null {
  if (typeof value !== "string") return null;
  const month = /^(\d{4})-(\d{2})$/.exec(value);
  const day = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  const full = month ? `${value}-01` : day ? value : null;
  if (!full) return null;
  const parsed = new Date(`${full}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== full) return null;
  return { date: full, precision: month ? "month" : "day" };
}

export type SuggestionContext = {
  today: string;
  entries: ReadonlyMap<string, SuggestionEntry>;
  chapters: readonly ExistingChapter[];
  /** Every earlier suggestion, pending, confirmed, or dismissed. */
  suggestions: readonly (KnownWindow & { status: string })[];
};

/**
 * Keeps only the suggestions that are safe to show. A suggestion that is wrong in any way is
 * dropped, never repaired: proposing nothing is a good answer.
 */
export function validateSuggestions(raw: unknown, ctx: SuggestionContext): ValidSuggestion[] {
  if (!isRow(raw) || !Array.isArray(raw.suggestions)) return [];
  const pending = ctx.suggestions.filter((item) => item.status === "pending").length;
  const room = Math.max(0, MAX_PENDING - pending);
  const entries = [...ctx.entries.values()];
  if (entries.length === 0) return [];
  const earliest = entries.reduce((a, b) => (a.windowStart <= b.windowStart ? a : b)).windowStart;
  const known: KnownWindow[] = [
    ...ctx.chapters,
    ...ctx.suggestions,
  ];
  const chapterTitles = new Set(ctx.chapters.map((chapter) => chapter.title.trim().toLowerCase()));
  const kept: ValidSuggestion[] = [];

  for (const item of raw.suggestions) {
    if (kept.length >= room || kept.length >= MAX_PENDING) break;
    if (!isRow(item)) continue;

    const name = typeof item.name === "string" ? item.name.normalize("NFC").trim() : "";
    if (
      name === "" ||
      codePointLength(name) > 80 ||
      /[\p{Zl}\p{Zp}\r\n]/u.test(name) ||
      chapterTitles.has(name.toLowerCase())
    )
      continue;

    const start = parsePoint(item.start);
    const end = item.end === null ? null : parsePoint(item.end);
    if (!start || (item.end !== null && !end)) continue;
    const windowStart = start.date;
    let windowEnd: string | null = null;
    if (end) {
      windowEnd = end.precision === "month" ? addMonths(end.date, 1) : addDays(end.date, 1);
      if (windowEnd <= windowStart) continue;
      // The end may not lie after today.
      const limit = end.precision === "month" ? addMonths(`${ctx.today.slice(0, 7)}-01`, 1) : addDays(ctx.today, 1);
      if (windowEnd > limit) continue;
    }
    // The start may not reach back before what was read.
    const floor = start.precision === "month" ? `${earliest.slice(0, 7)}-01` : earliest;
    if (windowStart < floor) continue;

    if (!Array.isArray(item.entries)) continue;
    const cited: SuggestionEntry[] = [];
    for (const ref of item.entries) {
      const entry = typeof ref === "string" ? ctx.entries.get(ref) : undefined;
      if (entry && !cited.includes(entry)) cited.push(entry);
    }
    if (cited.length < 4 || cited.length > 20) continue;
    const firstDay = cited.reduce((a, b) => (a < b.windowStart ? a : b.windowStart), cited[0].windowStart);
    const lastDay = cited.reduce((a, b) => (a > b.windowStart ? a : b.windowStart), cited[0].windowStart);
    if (dayNumber(lastDay) - dayNumber(firstDay) < 21) continue;

    // The Chapter rule: its window holds every Entry cited for it.
    if (cited.some((entry) => entry.windowStart < windowStart || (windowEnd !== null && entry.windowEnd > windowEnd)))
      continue;
    // Still going on is only believable when the newest cited Entry is recent.
    if (end === null && dayNumber(ctx.today) - dayNumber(lastDay) > 45) continue;

    const rationale = typeof item.rationale === "string" ? item.rationale.normalize("NFC").trim() : "";
    if (rationale === "" || codePointLength(rationale) > 400) continue;
    if (!quotationsHold(rationale, cited.map((entry) => `${entry.title}\n${entry.excerpt}`))) continue;

    const candidate: KnownWindow = { windowStart, windowEnd };
    if (known.some((other) => windowIou(candidate, other, ctx.today) >= 0.5)) continue;
    if (kept.some((other) => windowIou(candidate, other, ctx.today) >= 0.5)) continue;

    kept.push({
      name,
      rationale,
      sourceEntryIds: cited.map((entry) => entry.id),
      startDate: start.date,
      startPrecision: start.precision,
      endDate: end ? end.date : null,
      endPrecision: end ? end.precision : null,
      windowStart,
      windowEnd,
    });
  }
  return kept;
}

function labelFor(row: Row, span: boolean) {
  const timezone = validTimezone(row.occurredTimezone) ? row.occurredTimezone : "UTC";
  const occurrence = {
    occurredAt: text(row.occurredStart),
    occurredEnd: text(row.occurredEnd),
    occurredLabel: text(row.occurredLabel),
    occurredTimezone: timezone,
    datePrecision: (text(row.datePrecision) ?? "unknown") as OccurrencePrecision,
  };
  return span ? occurrenceSpanLabel(occurrence) : occurrenceLabel(occurrence);
}

export type SuggestionInputs = {
  entries: SuggestionEntry[];
  chapters: (ExistingChapter & { span: string })[];
  suggestions: (KnownWindow & { status: string })[];
};

export function parseSuggestionInputs(data: unknown): SuggestionInputs | null {
  if (!isRow(data) || !Array.isArray(data.entries) || !Array.isArray(data.chapters) || !Array.isArray(data.suggestions))
    return null;
  const entries: SuggestionEntry[] = [];
  for (const row of data.entries) {
    if (!isRow(row) || typeof row.id !== "string" || typeof row.windowStart !== "string") continue;
    const windowStart = row.windowStart;
    entries.push({
      ref: `S${entries.length + 1}`,
      id: row.id,
      title: text(row.title)?.trim() ?? "",
      excerpt: text(row.excerpt)?.trim() ?? "",
      tags: Array.isArray(row.tags) ? row.tags.filter((tag): tag is string => typeof tag === "string") : [],
      dateLabel: labelFor(row, false),
      windowStart,
      windowEnd: text(row.windowEnd) ?? addDays(windowStart, 1),
    });
  }
  const chapters: SuggestionInputs["chapters"] = [];
  for (const row of data.chapters) {
    if (!isRow(row) || typeof row.windowStart !== "string") continue;
    chapters.push({
      title: text(row.title)?.trim() || "Untitled Chapter",
      windowStart: row.windowStart,
      windowEnd: text(row.windowEnd),
      span: labelFor(row, true),
    });
  }
  const suggestions: SuggestionInputs["suggestions"] = [];
  for (const row of data.suggestions) {
    if (!isRow(row) || typeof row.windowStart !== "string" || typeof row.status !== "string") continue;
    suggestions.push({ status: row.status, windowStart: row.windowStart, windowEnd: text(row.windowEnd) });
  }
  return { entries, chapters, suggestions };
}

const clip = (value: string, limit: number) => Array.from(value).slice(0, limit).join("");

/**
 * The input the model reads: newest Entries first, excerpts shortened and then the oldest Entries
 * dropped until it fits. Returns the entries actually sent, in order.
 */
export function fitSuggestionInput(
  inputs: SuggestionInputs,
  today: string,
): { entries: SuggestionEntry[]; input: string } {
  const spans = inputs.suggestions.map((item) => ({
    span: monthSpanLabel([{ windowStart: item.windowStart, windowEnd: item.windowEnd ?? addDays(today, 1) }]),
  }));
  const build = (entries: SuggestionEntry[]) => {
    const prompt: SuggestionPromptEntry[] = entries.map((entry) => ({
      id: entry.ref,
      date: entry.dateLabel,
      title: entry.title,
      tags: entry.tags,
      excerpt: entry.excerpt,
      excerptOnly: true,
    }));
    return buildChapterSuggestionInput({
      today,
      entries: prompt,
      existingChapters: inputs.chapters.map((chapter) => ({ name: chapter.title, span: chapter.span })),
      earlierSuggestions: spans,
    });
  };
  const size = (value: string) => Buffer.byteLength(value, "utf8");

  let entries = inputs.entries;
  let input = build(entries);
  if (size(input) <= SUGGESTION_MAX_BYTES) return { entries, input };
  entries = entries.map((entry) => ({ ...entry, excerpt: clip(entry.excerpt, EXCERPT_CODE_POINTS) }));
  input = build(entries);
  if (size(input) <= SUGGESTION_MAX_BYTES) return { entries, input };
  // Drop the oldest by halving the overshoot, then settle one by one.
  let count = entries.length;
  while (count > 0) {
    count = Math.min(count - 1, Math.floor((count * SUGGESTION_MAX_BYTES) / size(input)));
    entries = entries.slice(0, Math.max(count, 0));
    input = build(entries);
    if (size(input) <= SUGGESTION_MAX_BYTES) break;
  }
  return { entries, input };
}

/** The first day of the month `LOOKBACK_MONTHS` before today: the oldest Entry a run reads. */
export function suggestionHorizon(today: string) {
  return addMonths(`${today.slice(0, 7)}-01`, -LOOKBACK_MONTHS);
}

export type SuggestionRunResult =
  | { status: "skipped" }
  | { status: "stored"; stored: number }
  | { status: "released"; code: string };

/** Errors that mean nothing was charged, or the provider said plainly that it failed. */
const RELEASABLE = new Set([
  "provider_unavailable",
  "ai_disabled",
  "budget_exceeded",
  "rate_limit",
  "request_too_large",
  "usage_unavailable",
  "invalid_budget",
  "ai_paused",
  "provider_error",
  "provider_authentication",
]);

async function recordRun(client: SupabaseClient, lease: string, suggestions: ValidSuggestion[], model: string) {
  const stored = await client.rpc("store_chapter_suggestions", {
    p_lease_until: lease,
    p_suggestions: suggestions,
    p_model: model,
    p_disclosure_version: REVIEW_DISCLOSURE_VERSION,
  });
  return typeof stored.data === "number" ? stored.data : 0;
}

/**
 * Looks at recent Entries once in a while and proposes Chapters, only for people who turned
 * Suggest Chapters on. The claim makes repeated calls cheap no-ops, and a run that cannot tell
 * what happened is recorded as empty so it waits rather than being retried and charged again.
 */
export async function runChapterSuggestions(
  client: SupabaseClient,
  ownerID: string,
  today: string,
): Promise<SuggestionRunResult> {
  const claim = await client.rpc("claim_chapter_suggestion_run");
  if (claim.error || !isRow(claim.data) || claim.data.due !== true || typeof claim.data.leaseUntil !== "string")
    return { status: "skipped" };
  const lease = claim.data.leaseUntil;
  const release = async (code: string): Promise<SuggestionRunResult> => {
    await client.rpc("release_chapter_suggestion_run", { p_lease_until: lease });
    return { status: "released", code };
  };

  const read = await client.rpc("chapter_suggestion_inputs", { p_since: suggestionHorizon(today) });
  const inputs = read.error ? null : parseSuggestionInputs(read.data);
  if (!inputs) return release("inputs_unavailable");

  if (inputs.entries.length < SUGGESTION_MIN_ENTRIES) {
    return { status: "stored", stored: await recordRun(client, lease, [], REVIEW_MODEL) };
  }
  const fitted = fitSuggestionInput(inputs, today);
  if (fitted.entries.length < SUGGESTION_MIN_ENTRIES) {
    return { status: "stored", stored: await recordRun(client, lease, [], REVIEW_MODEL) };
  }

  let answer: Awaited<ReturnType<typeof requestAI>>;
  try {
    answer = await requestAI({
      ownerID,
      feature: "chapter_suggestion",
      system: chapterSuggestionSystemPrompt,
      input: fitted.input,
      maxTokens: 6000,
      schema: chapterSuggestionSchema as unknown as Record<string, unknown>,
      effort: "low",
      timeoutMs: 120_000,
    });
  } catch (error) {
    if (error instanceof AIError && RELEASABLE.has(error.code)) return release(error.code);
    // Billing is uncertain, the model declined, or the answer was cut off: wait out the month.
    await recordRun(client, lease, [], REVIEW_MODEL);
    return { status: "stored", stored: 0 };
  }

  let suggestions: ValidSuggestion[] = [];
  try {
    suggestions = validateSuggestions(parseModelJson(answer.text), {
      today,
      entries: new Map(fitted.entries.map((entry) => [entry.ref, entry])),
      chapters: inputs.chapters,
      suggestions: inputs.suggestions,
    });
  } catch {
    suggestions = [];
  }
  return { status: "stored", stored: await recordRun(client, lease, suggestions, answer.model) };
}
