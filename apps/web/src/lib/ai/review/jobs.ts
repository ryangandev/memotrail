import "server-only";
import { createHash } from "node:crypto";
import type { SupabaseClient } from "@supabase/supabase-js";
import { aiModelPricing, REVIEW_MODEL } from "../contracts";
import { REVIEW_DISCLOSURE_VERSION } from "../review-disclosure";
import { AIError, aiAdminClient, aiMonthlyBudgets, requestAI } from "../server";
import {
  GroundingError,
  parseModelJson,
  resolveMap,
  resolveReview,
  type Candidate,
  type GroundingContext,
  type GroundingEntry,
  type MapResult,
} from "./grounding";
import { chooseReviewLanguage, type ReviewLanguage } from "./language";
import {
  estimateJobMicros,
  packPeriod,
  sentPassages,
  STEP_MAX_TOKENS,
  type PackableEntry,
} from "./packing";
import {
  loadPeriod,
  monthSpanLabel,
  PeriodError,
  type PeriodEntry,
  type ReviewSubject,
} from "./period";
import {
  buildMapInput,
  buildReduceInput,
  buildReviewInput,
  mapSchema,
  mapSystemPrompt,
  reduceSystemPrompt,
  REVIEW_PROMPT_VERSION,
  reviewSchema,
  reviewSystemPrompt,
  type PromptEntry,
  type PromptSubject,
  type ReduceCandidate,
  type ReducePart,
} from "./prompts";

export type StartedReview = {
  reviewId: string;
  jobStartedAt: string;
  done: number;
  total: number;
};

type StepState = {
  index: number;
  kind: "review" | "map" | "reduce";
  entryIds: string[];
  status: string;
  result?: unknown;
};

type JobState = {
  disclosureVersion: string;
  planHash: string;
  mode: "single" | "segmented";
  entryIds: string[];
  noteEntryId: string | null;
  entriesInPeriod: number;
  trimmedEntries: number;
  trimCodePoints: number | null;
  language: ReviewLanguage;
  subject: ReviewSubject;
  steps: StepState[];
};

type Row = Record<string, unknown>;
const isRow = (value: unknown): value is Row =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** Reads the job the database handed back, refusing anything that is not the shape this code wrote. */
export function parseJobState(value: unknown): JobState | null {
  if (!isRow(value) || !Array.isArray(value.steps) || !Array.isArray(value.entryIds)) return null;
  const subject = isRow(value.subject) ? value.subject : null;
  const parsedSubject: ReviewSubject | null =
    subject?.scope === "chapter" && typeof subject.chapterId === "string"
      ? { scope: "chapter", chapterId: subject.chapterId }
      : subject?.scope === "year" && Number.isInteger(subject.year)
        ? { scope: "year", year: subject.year as number }
        : null;
  if (
    !parsedSubject ||
    (value.mode !== "single" && value.mode !== "segmented") ||
    (value.language !== "en" && value.language !== "zh") ||
    typeof value.planHash !== "string" ||
    typeof value.disclosureVersion !== "string" ||
    !Number.isInteger(value.entriesInPeriod) ||
    !Number.isInteger(value.trimmedEntries)
  )
    return null;
  const steps: StepState[] = [];
  for (const step of value.steps) {
    if (
      !isRow(step) ||
      !Number.isInteger(step.index) ||
      (step.kind !== "review" && step.kind !== "map" && step.kind !== "reduce") ||
      !Array.isArray(step.entryIds) ||
      typeof step.status !== "string"
    )
      return null;
    steps.push({
      index: step.index as number,
      kind: step.kind,
      entryIds: step.entryIds.filter((id): id is string => typeof id === "string"),
      status: step.status,
      result: step.result,
    });
  }
  return {
    disclosureVersion: value.disclosureVersion,
    planHash: value.planHash,
    mode: value.mode,
    entryIds: value.entryIds.filter((id): id is string => typeof id === "string"),
    noteEntryId: typeof value.noteEntryId === "string" ? value.noteEntryId : null,
    entriesInPeriod: value.entriesInPeriod as number,
    trimmedEntries: value.trimmedEntries as number,
    trimCodePoints: typeof value.trimCodePoints === "number" ? value.trimCodePoints : null,
    language: value.language,
    subject: parsedSubject,
    steps,
  };
}

const SERVER_ERRORS: Record<string, [string, number, string]> = {
  ai_disabled: ["review_consent_required", 403, "Turn on reviews in Settings first."],
  review_disclosure_outdated: [
    "review_consent_required",
    403,
    "Review the updated disclosure in Settings first.",
  ],
  review_not_eligible: [
    "review_not_eligible",
    409,
    "This review can't be made right now. Reload to see its current state.",
  ],
  review_in_progress: [
    "review_in_progress",
    409,
    "Another review is being written. Try again when it finishes.",
  ],
  review_limit_reached: [
    "review_limit_reached",
    429,
    "You've made this review three times today. Try again tomorrow.",
  ],
};

function claimError(message: string | undefined) {
  const known = message ? SERVER_ERRORS[message] : undefined;
  return known
    ? new AIError(known[0], known[1], known[2])
    : new AIError("review_unavailable", 503, "Reviews are unavailable right now. Your Entries are unchanged.");
}

function sha256(value: unknown) {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

/**
 * Plans a review of the subject as it is now and claims the job. Nothing is sent to the provider
 * here; the steps run in `advanceReview`, which reads the writing again with the person's session.
 */
export async function startReview(
  client: SupabaseClient,
  ownerID: string,
  subject: ReviewSubject,
  localDate: string,
): Promise<StartedReview> {
  const read =
    subject.scope === "chapter"
      ? await client.rpc("chapter_review", { p_chapter_id: subject.chapterId, p_local_date: localDate })
      : await client.rpc("year_review", { p_year: subject.year, p_local_date: localDate });
  if (read.error || !isRow(read.data)) throw claimError(undefined);
  const settings = isRow(read.data.settings) ? read.data.settings : {};
  if (settings.reviewsEnabled !== true || settings.disclosureVersion !== REVIEW_DISCLOSURE_VERSION)
    throw claimError("ai_disabled");
  const eligibility = isRow(read.data.eligibility) ? read.data.eligibility : {};
  if (eligibility.status !== "eligible") throw claimError("review_not_eligible");

  let period: Awaited<ReturnType<typeof loadPeriod>>;
  try {
    period = await loadPeriod(client, subject);
  } catch (error) {
    if (error instanceof PeriodError && error.code === "review_not_eligible")
      throw claimError("review_not_eligible");
    throw claimError(undefined);
  }
  const readable: PackableEntry[] = period.entries
    // A blank note has nothing to read, so it is not part of the plan.
    .filter((entry) => !entry.isSubject || entry.body.trim() !== "")
    .map((entry) => ({
      id: entry.id,
      isSubject: entry.isSubject,
      title: entry.title,
      body: entry.body,
      tags: entry.tags,
      isFirstTime: entry.isFirstTime,
    }));
  const packed = packPeriod(readable);
  if (packed.entriesRead === 0) throw claimError("review_not_eligible");

  const kept = new Set(packed.entryIds);
  const language = chooseReviewLanguage(
    period.entries.filter((entry) => kept.has(entry.id)).map((entry) => `${entry.title}\n${entry.body}`),
  );
  const revision = new Map(period.entries.map((entry) => [entry.id, entry.revision]));
  const steps = packed.steps.map((step) => ({ index: step.index, kind: step.kind, entryIds: step.entryIds }));
  const planHash = sha256({
    entries: packed.entryIds.map((id) => [id, revision.get(id)]),
    mode: packed.mode,
    steps: steps.map((step) => [step.kind, step.entryIds]),
    model: REVIEW_MODEL,
    promptVersion: REVIEW_PROMPT_VERSION,
    trim: packed.trimCodePoints,
    language,
  });

  const budgets = aiMonthlyBudgets();
  if (!budgets)
    throw new AIError("invalid_budget", 503, "The server AI budget needs configuration.");
  const estimate = estimateJobMicros(packed.steps, aiModelPricing[REVIEW_MODEL]);
  const allowed = await aiAdminClient().rpc("ai_budget_allows", {
    p_owner_id: ownerID,
    p_estimated_micros: estimate,
    p_global_budget_micros: budgets.server,
    p_user_budget_micros: budgets.user,
  });
  if (allowed.error) throw claimError(undefined);
  if (allowed.data !== true)
    throw new AIError(
      "budget_exceeded",
      429,
      "This month's review allowance is used up. It renews on the first of next month.",
    );

  const claimed = await client.rpc("claim_entry_review", {
    p_scope: subject.scope,
    p_chapter_id: subject.scope === "chapter" ? subject.chapterId : null,
    p_year: subject.scope === "year" ? subject.year : null,
    p_local_date: localDate,
    p_plan: {
      disclosureVersion: REVIEW_DISCLOSURE_VERSION,
      planHash,
      mode: packed.mode,
      entryIds: packed.entryIds,
      noteEntryId: packed.noteEntryId,
      entriesInPeriod: packed.entriesInPeriod,
      trimmedEntries: packed.trimmedEntries,
      trimCodePoints: packed.trimCodePoints,
      language,
      ongoing: eligibility.ongoing === true,
      subject,
      steps,
    },
  });
  if (claimed.error || !isRow(claimed.data)) throw claimError(claimed.error?.message);
  const { reviewId, jobStartedAt, done, total } = claimed.data;
  if (
    typeof reviewId !== "string" ||
    typeof jobStartedAt !== "string" ||
    !Number.isInteger(done) ||
    !Number.isInteger(total)
  )
    throw claimError(undefined);
  return { reviewId, jobStartedAt, done: done as number, total: total as number };
}

type StepOutcome = "finished" | "stopped";

/** A wave may start only when it can finish inside the function's time limit. */
const WAVE_BUDGET_MS = 280_000;
const LONGEST_STEP_MS = 245_000;

/**
 * Runs the steps that are ready, at most one wave at a time. A second wave (the final step of a
 * long period) runs in the same invocation only when the time left allows it; otherwise the next
 * poll of the status route resumes the job without repeating any request that was paid for.
 */
export async function advanceReview(
  client: SupabaseClient,
  ownerID: string,
  reviewId: string,
  jobStartedAt: string,
) {
  const deadline = Date.now() + WAVE_BUDGET_MS;
  for (let wave = 0; wave < 2; wave += 1) {
    const claim = await client.rpc("claim_review_steps", {
      p_review_id: reviewId,
      p_job_started_at: jobStartedAt,
      p_max: 6,
    });
    if (claim.error || !isRow(claim.data) || claim.data.status !== "ok") return;
    const claimed = Array.isArray(claim.data.claimed)
      ? claim.data.claimed.filter((index): index is number => Number.isInteger(index))
      : [];
    if (claimed.length === 0) return;
    const state = parseJobState(claim.data.state);
    if (!state) {
      await failJob(client, reviewId, jobStartedAt, "generation_failed");
      return;
    }
    let period: Awaited<ReturnType<typeof loadPeriod>>;
    try {
      period = await loadPeriod(client, state.subject);
    } catch {
      await failJob(client, reviewId, jobStartedAt, "generation_failed");
      return;
    }
    const outcomes = await Promise.all(
      claimed.map((index) =>
        runStep({ client, ownerID, reviewId, jobStartedAt, state, period, index }),
      ),
    );
    if (outcomes.includes("stopped")) return;
    if (deadline - Date.now() < LONGEST_STEP_MS) return;
  }
}

async function failJob(client: SupabaseClient, reviewId: string, jobStartedAt: string, code: string) {
  await client
    .rpc("fail_entry_review", {
      p_review_id: reviewId,
      p_job_started_at: jobStartedAt,
      p_error_code: code,
    })
    .then(
      () => undefined,
      () => undefined,
    );
}

function failureCode(error: unknown) {
  if (error instanceof AIError || error instanceof GroundingError) return error.code;
  const message = isRow(error) && typeof error.message === "string" ? error.message : "";
  return /^[a-z0-9_]{1,64}$/.test(message) ? message : "generation_failed";
}

type StepContext = {
  client: SupabaseClient;
  ownerID: string;
  reviewId: string;
  jobStartedAt: string;
  state: JobState;
  period: Awaited<ReturnType<typeof loadPeriod>>;
  index: number;
};

async function runStep(context: StepContext): Promise<StepOutcome> {
  const { client, ownerID, reviewId, jobStartedAt, state, period, index } = context;
  try {
    const step = state.steps.find((item) => item.index === index);
    if (!step) throw new GroundingError("invalid_review");

    // Reviews may have been turned off, or the disclosure changed, since the job began.
    const settings = await client.rpc("review_settings");
    if (
      settings.error ||
      !isRow(settings.data) ||
      settings.data.reviewsEnabled !== true ||
      settings.data.disclosureVersion !== state.disclosureVersion
    ) {
      await failJob(client, reviewId, jobStartedAt, "ai_disabled");
      return "stopped";
    }

    const byId = new Map(period.entries.map((entry) => [entry.id, entry]));
    // Numbers belong to the plan, so they mean the same Entry in every step.
    const refs = new Map<string, string>();
    let next = 1;
    for (const id of state.entryIds) refs.set(id, id === state.noteEntryId ? "E0" : `E${next++}`);
    const subjectEntry = period.entries.find((entry) => entry.isSubject);
    const subject: PromptSubject =
      state.subject.scope === "chapter"
        ? {
            kind: "chapter",
            name: subjectEntry?.title || "This Chapter",
            span: subjectEntry?.dateLabel ?? "Date unknown",
            note: state.noteEntryId ? "E0" : null,
          }
        : { kind: "year", year: state.subject.year };

    if (step.kind === "reduce")
      return await runReduce(context, { byId, refs, subject });

    // Entries trashed since the plan was made are left out; deleted ones already failed the job.
    const present = step.entryIds.flatMap((id) => {
      const entry = byId.get(id);
      return entry ? [entry] : [];
    });
    const prepared = present.map((entry) => {
      const ref = refs.get(entry.id)!;
      const sent = sentPassages(entry.body, state.trimCodePoints);
      return { entry, ref, sent };
    });
    const promptEntries: PromptEntry[] = prepared.map(({ entry, ref, sent }) => ({
      id: ref,
      role: entry.isSubject ? "chapter_note" : "entry",
      date: entry.dateLabel,
      title: entry.title,
      tags: entry.tags,
      firstTime: entry.isFirstTime,
      trimmed: sent.trimmed,
      passages: sent.passages.map((passage) => ({ id: `${ref}.P${passage.id}`, text: passage.text })),
    }));
    const groundingEntries = new Map<string, GroundingEntry>(
      prepared.map(({ entry, ref, sent }) => [
        ref,
        {
          ref,
          id: entry.id,
          revision: entry.revision,
          isNote: entry.isSubject,
          body: entry.body,
          windowStart: entry.windowStart,
          windowEnd: entry.windowEnd,
          passages: new Map(sent.passages.map((passage) => [passage.id, passage])),
          sentText: sent.passages.map((passage) => passage.text).join("\n"),
        },
      ]),
    );
    const entriesSent = prepared.filter(({ entry }) => !entry.isSubject).length;
    const selection = {
      entriesInPeriod: state.entriesInPeriod,
      entriesSent,
      trimmedEntries: prepared.filter(({ entry, sent }) => !entry.isSubject && sent.trimmed).length,
    };
    const chapters = state.subject.scope === "year" ? period.chapters : [];
    const common = { language: state.language, subject, selection, chapters };
    const context_: GroundingContext = {
      entries: groundingEntries,
      entriesInPeriod: state.entriesInPeriod,
    };
    const read = prepared.map(({ entry }) => ({ entryId: entry.id, revision: entry.revision }));

    if (step.kind === "map") {
      const maps = state.steps.filter((item) => item.kind === "map");
      const answer = await requestAI({
        ownerID,
        feature: "review",
        system: mapSystemPrompt,
        input: buildMapInput({
          ...common,
          entries: promptEntries,
          part: { index: maps.findIndex((item) => item.index === index) + 1, of: maps.length, dates: monthSpanLabel(present) },
        }),
        maxTokens: STEP_MAX_TOKENS.map,
        schema: mapSchema as unknown as Record<string, unknown>,
        effort: "medium",
        timeoutMs: 180_000,
      });
      const result = resolveMap(parseModelJson(answer.text), context_);
      const finished = await client.rpc("finish_review_step", {
        p_review_id: reviewId,
        p_job_started_at: jobStartedAt,
        p_step: index,
        p_result: { ...result, read },
      });
      return finished.error || finished.data !== true ? "stopped" : "finished";
    }

    const answer = await requestAI({
      ownerID,
      feature: "review",
      system: reviewSystemPrompt,
      input: buildReviewInput({ ...common, entries: promptEntries }),
      maxTokens: STEP_MAX_TOKENS.review,
      schema: reviewSchema as unknown as Record<string, unknown>,
      effort: "medium",
    });
    const content = resolveReview(parseModelJson(answer.text), context_);
    return await storeReview(context, content, answer.model, entriesSent, read);
  } catch (error) {
    await failJob(client, reviewId, jobStartedAt, failureCode(error));
    return "stopped";
  }
}

async function storeReview(
  context: StepContext,
  content: unknown,
  model: string,
  entriesRead: number,
  sources: { entryId: string; revision: number }[],
): Promise<StepOutcome> {
  const stored = await context.client.rpc("store_entry_review", {
    p_review_id: context.reviewId,
    p_job_started_at: context.jobStartedAt,
    p_content: content,
    p_model: model,
    p_entries_read: entriesRead,
    p_sources: sources,
  });
  if (stored.error) throw { message: stored.error.message };
  return stored.data === true ? "finished" : "stopped";
}

function mapResultOf(step: StepState): (MapResult & { read: { entryId: string; revision: number }[] }) | null {
  const result = step.result;
  if (
    !isRow(result) ||
    typeof result.notes !== "string" ||
    !Array.isArray(result.arc) ||
    !Array.isArray(result.themes) ||
    !Array.isArray(result.quotes) ||
    !Array.isArray(result.read)
  )
    return null;
  return result as unknown as MapResult & { read: { entryId: string; revision: number }[] };
}

async function runReduce(
  context: StepContext,
  shared: { byId: Map<string, PeriodEntry>; refs: Map<string, string>; subject: PromptSubject },
): Promise<StepOutcome> {
  const { ownerID, state, period } = context;
  const { byId, refs, subject } = shared;
  const idOf = new Map([...refs].map(([id, ref]) => [ref, id]));
  const maps = state.steps.filter((item) => item.kind === "map");
  const results = maps.map((item) => ({ step: item, result: mapResultOf(item) }));
  if (results.some((item) => !item.result)) throw new GroundingError("invalid_review");

  const presentRef = (ref: string) => {
    const id = idOf.get(ref);
    return id !== undefined && byId.has(id);
  };
  const candidates: (Candidate & { part: number })[] = [];
  const parts: ReducePart[] = results.map(({ step: item, result }, partIndex) => {
    const members = item.entryIds.flatMap((id) => (byId.has(id) ? [byId.get(id)!] : []));
    for (const quote of result!.quotes) {
      const entry = byId.get(idOf.get(quote.ref) ?? "");
      if (!entry || !entry.body.includes(quote.text)) continue;
      candidates.push({
        from: quote.from,
        to: quote.to,
        ref: quote.ref,
        start: quote.start,
        end: quote.end,
        text: quote.text,
        part: partIndex,
      });
    }
    return {
      index: partIndex + 1,
      dates: monthSpanLabel(members),
      entryCount: members.filter((entry) => !entry.isSubject).length,
      notes: result!.notes,
      arc: result!.arc
        .map((phase) => ({ ...phase, entries: phase.entries.filter(presentRef) }))
        .filter((phase) => phase.entries.length > 0),
      themes: result!.themes
        .map((theme) => ({ ...theme, entries: theme.entries.filter(presentRef) }))
        .filter((theme) => theme.entries.length > 0),
    };
  });

  const cited = new Set<string>();
  for (const part of parts) {
    for (const phase of part.arc) phase.entries.forEach((ref) => cited.add(ref));
    for (const theme of part.themes) theme.entries.forEach((ref) => cited.add(ref));
  }
  for (const candidate of candidates) cited.add(candidate.ref);

  const grounding = new Map<string, GroundingEntry>();
  for (const ref of cited) {
    const entry = byId.get(idOf.get(ref)!)!;
    grounding.set(ref, {
      ref,
      id: entry.id,
      revision: entry.revision,
      isNote: entry.isSubject,
      body: entry.body,
      windowStart: entry.windowStart,
      windowEnd: entry.windowEnd,
      passages: new Map(),
      sentText: candidates
        .filter((candidate) => candidate.ref === ref)
        .map((candidate) => candidate.text)
        .join("\n"),
    });
  }

  const promptCandidates: ReduceCandidate[] = candidates.map((candidate) => ({
    from: candidate.from,
    to: candidate.to,
    entry: candidate.ref,
    date: byId.get(idOf.get(candidate.ref)!)!.dateLabel,
    text: candidate.text,
  }));
  const sentEntries = [...new Set(results.flatMap(({ result }) => result!.read.map((item) => item.entryId)))].filter(
    (id) => byId.has(id),
  );
  const entriesRead = sentEntries.filter((id) => id !== state.noteEntryId).length;
  const selection = {
    entriesInPeriod: state.entriesInPeriod,
    entriesSent: entriesRead,
    trimmedEntries: state.trimmedEntries,
  };

  const answer = await requestAI({
    ownerID,
    feature: "review",
    system: reduceSystemPrompt,
    input: buildReduceInput({
      language: state.language,
      subject,
      selection,
      chapters: state.subject.scope === "year" ? period.chapters : [],
      parts,
      entries: [...cited]
        .filter((ref) => !grounding.get(ref)!.isNote)
        .map((ref) => ({
          id: ref,
          date: byId.get(idOf.get(ref)!)!.dateLabel,
          title: byId.get(idOf.get(ref)!)!.title,
        })),
      candidateQuotes: promptCandidates,
    }),
    maxTokens: STEP_MAX_TOKENS.reduce,
    schema: reviewSchema as unknown as Record<string, unknown>,
    effort: "medium",
  });
  const content = resolveReview(parseModelJson(answer.text), {
    entries: grounding,
    entriesInPeriod: state.entriesInPeriod,
    candidates,
  });
  const revisionRead = new Map(
    results.flatMap(({ result }) => result!.read.map((item) => [item.entryId, item.revision] as const)),
  );
  return await storeReview(
    context,
    content,
    answer.model,
    entriesRead,
    sentEntries.map((entryId) => ({ entryId, revision: revisionRead.get(entryId)! })),
  );
}
