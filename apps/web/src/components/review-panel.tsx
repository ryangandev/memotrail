"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState, type ReactNode } from "react";
import { saveReviewPreferences } from "@/app/reviews/actions";
import { notify } from "@/components/app-toast";
import { Badge } from "@/components/badge";
import { Button } from "@/components/button";
import { useConfirmationDialog } from "@/components/confirmation-dialog";
import { ReviewDisclosureDialog } from "@/components/review-disclosure-dialog";
import styles from "@/components/review-panel.module.css";
import { SectionHeader } from "@/components/section-header";
import { SeparatedList } from "@/components/separated-list";
import { Skeleton } from "@/components/skeleton";
import {
  chapterSendsLine,
  REVIEW_DISCLOSURE_VERSION,
  REVIEW_FOOTER,
  yearSendsLine,
} from "@/lib/ai/review-disclosure";
import {
  entryDisplayTitle,
  occurrenceLabel,
  occurrenceSpanLabel,
  validTimezone,
  type Occurrence,
} from "@/lib/data/occurrence";
import {
  monthLabel,
  phaseRangeLabel,
  phasesSpanYears,
  reviewFailureMessage,
  type ReviewEntryRef,
  type ReviewPageData,
  type ReviewSettings,
  type StoredReview,
} from "@/lib/data/review-input";

export type ReviewSubjectProp =
  { scope: "chapter"; chapterId: string } | { scope: "year"; year: number };

type Job = { reviewId: string; done: number; total: number };

const POLL_MS = 4_000;

function occurrenceOf(ref: ReviewEntryRef): Occurrence {
  return {
    occurredAt: ref.occurredStart,
    occurredEnd: ref.occurredEnd,
    occurredLabel: ref.occurredLabel,
    occurredTimezone: validTimezone(ref.occurredTimezone)
      ? ref.occurredTimezone
      : "UTC",
    datePrecision: ref.datePrecision,
  };
}

const plural = (count: number, one: string, many: string) =>
  `${count} ${count === 1 ? one : many}`;

/**
 * A review of a Chapter or a year: the facts from the person's own records, Claude's
 * interpretation (labeled as such), and their own words, quoted exactly. A review is made only
 * when the person asks, and everything on it can be checked against their Entries.
 */
export function ReviewPanel({
  data,
  preferences,
  spanLabel,
  subject,
  timezone,
  today,
}: {
  data: ReviewPageData;
  preferences: ReviewSettings;
  /** The Chapter's dates, such as "Mar 2026 - May 2026", for the records block. */
  spanLabel?: string;
  subject: ReviewSubjectProp;
  timezone: string;
  today: string;
}) {
  const router = useRouter();
  const requestConfirmation = useConfirmationDialog();
  const { eligibility, review } = data;
  const eligible = eligibility.status === "eligible";

  const [prefs, setPrefs] = useState(preferences);
  const [job, setJob] = useState<Job | null>(() => jobFrom(review));
  const [failure, setFailure] = useState<string | null>(null);
  const [starting, setStarting] = useState(false);
  const [dialogOpen, setDialogOpen] = useState(false);

  // A refreshed page is the truth about the job and the settings: follow it, and forget a
  // failure from the last request.
  const [seen, setSeen] = useState({ preferences, review });
  if (seen.review !== review || seen.preferences !== preferences) {
    setSeen({ preferences, review });
    setJob(jobFrom(review));
    setFailure(null);
    setPrefs(preferences);
  }

  const reviewId = job?.reviewId ?? null;
  useEffect(() => {
    if (!reviewId) return;
    let stopped = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    async function poll() {
      if (stopped) return;
      if (document.visibilityState !== "hidden") {
        try {
          const response = await fetch(`/api/reviews/${reviewId}`, {
            cache: "no-store",
            method: "POST",
          });
          if (response.status === 404) {
            stopped = true;
            router.refresh();
            return;
          }
          if (response.ok) {
            const body = (await response.json()) as {
              status?: string;
              done?: number;
              total?: number;
            };
            // The database says "idle" once a job has finished and stored its review; only
            // "generating" means more is coming.
            if (body.status && body.status !== "generating") {
              stopped = true;
              router.refresh();
              return;
            }
            setJob((current) =>
              current &&
              typeof body.done === "number" &&
              typeof body.total === "number"
                ? { ...current, done: body.done, total: body.total }
                : current,
            );
          }
        } catch {
          /* A dropped connection is retried on the next beat. */
        }
      }
      if (!stopped) timer = setTimeout(() => void poll(), POLL_MS);
    }
    timer = setTimeout(() => void poll(), POLL_MS / 2);
    return () => {
      stopped = true;
      if (timer) clearTimeout(timer);
    };
  }, [reviewId, router]);

  const needsDisclosure =
    !prefs.reviewsEnabled ||
    prefs.disclosureVersion !== REVIEW_DISCLOSURE_VERSION;

  async function run(acceptFirst: boolean) {
    if (starting) return;
    setStarting(true);
    setFailure(null);
    try {
      if (acceptFirst) {
        const saved = await saveReviewPreferences({
          acceptDisclosure: true,
          reviews: true,
          revision: prefs.revision,
          suggestions: prefs.chapterSuggestionsEnabled,
        });
        if (saved.status !== "saved") {
          notify.error(saved.message);
          if (saved.status === "stale") router.refresh();
          return;
        }
        setPrefs(saved.settings);
      }
      const response = await fetch("/api/reviews", {
        body: JSON.stringify(
          subject.scope === "chapter"
            ? { chapterId: subject.chapterId, scope: "chapter" }
            : { scope: "year", year: subject.year },
        ),
        headers: { "Content-Type": "application/json" },
        method: "POST",
      });
      const body = (await response.json().catch(() => null)) as {
        code?: string;
        done?: number;
        reviewId?: string;
        total?: number;
      } | null;
      setDialogOpen(false);
      if (response.status === 202 && body?.reviewId) {
        setJob({
          done: body.done ?? 0,
          reviewId: body.reviewId,
          total: body.total ?? 1,
        });
        router.refresh();
        return;
      }
      if (body?.code === "review_not_eligible") router.refresh();
      setFailure(body?.code ?? "unavailable");
    } catch {
      setDialogOpen(false);
      setFailure("unavailable");
    } finally {
      setStarting(false);
    }
  }

  function begin() {
    if (needsDisclosure) setDialogOpen(true);
    else void run(false);
  }

  async function remove() {
    if (!review) return;
    const confirmed = await requestConfirmation({
      confirmLabel: "Delete review",
      description: (
        <>
          The review is deleted. Your Entries are not changed, and you can make
          a new review later.
        </>
      ),
      eyebrow: <>Deletes this review</>,
      title: <>Delete this review?</>,
      variant: "danger",
    });
    if (!confirmed) return;
    try {
      const response = await fetch(`/api/reviews/${review.id}`, {
        method: "DELETE",
      });
      if (!response.ok) throw Error();
      notify.info("Review deleted.");
      router.refresh();
    } catch {
      notify.error("MemoTrail could not delete this review. Try again.");
    }
  }

  const hasContent = Boolean(review?.content);
  if (!hasContent && !job && !eligible) return null;

  const isYear = subject.scope === "year";
  const ongoing = review?.content ? review.ongoing : eligibility.ongoing;
  const title = ongoing ? "Review so far" : "Review";
  const headingId = `review-heading-${isYear ? "year" : "chapter"}`;
  const failedJob = review?.job.status === "failed" ? review.job : null;
  const failureCode = failure ?? failedJob?.error ?? null;
  const failureText =
    failureCode && !job
      ? reviewFailureMessage(
          failureCode,
          today,
          failure === null && (failedJob?.done ?? 0) > 0,
        )
      : null;
  // Try again only makes sense after a job stopped; any other failure is retried by Make a review.
  const canRetry = failure === null && failedJob !== null && eligible;

  const actionBusy = starting || Boolean(job);

  return (
    <section
      aria-labelledby={headingId}
      className={styles.panel}
      data-ui-review-panel
    >
      {hasContent && review?.content ? (
        <ReadyHeader
          headingId={headingId}
          onDelete={() => void remove()}
          onNew={eligible ? begin : null}
          busy={actionBusy}
          review={review}
          timezone={timezone}
          title={title}
        />
      ) : (
        <SectionHeader
          description={startDescription(isYear, ongoing)}
          headingId={headingId}
          title={title}
        />
      )}

      {failureText ? (
        <div className={styles.failure} role="alert">
          <p>{failureText}</p>
          {canRetry ? (
            <Button
              disabled={actionBusy}
              loading={starting}
              onClick={begin}
              variant="secondary"
            >
              Try again
            </Button>
          ) : null}
        </div>
      ) : null}

      {job ? <Progress count={eligibility.entryCount} job={job} /> : null}

      {!hasContent && !job && eligible ? (
        <div className={styles.start}>
          <p className={styles.muted}>
            {subject.scope === "year"
              ? yearSendsLine(eligibility.entryCount, subject.year)
              : chapterSendsLine(eligibility.entryCount)}
          </p>
          {canRetry ? null : (
            <div>
              <Button loading={starting} onClick={begin} variant="primary">
                Make a review
              </Button>
            </div>
          )}
        </div>
      ) : null}

      {hasContent && review?.content ? (
        <>
          {job ? <p className={styles.previous}>Previous review</p> : null}
          <ReadyBody
            data={data}
            isYear={isYear}
            onNew={eligible && !job ? begin : null}
            review={review}
            spanLabel={spanLabel}
            subject={subject}
          />
        </>
      ) : null}

      <ReviewDisclosureDialog
        busy={starting}
        confirmLabel="Turn on and make review"
        onClose={() => setDialogOpen(false)}
        onConfirm={() => void run(true)}
        open={dialogOpen}
      />
    </section>
  );
}

function jobFrom(review: StoredReview | null): Job | null {
  return review?.job.status === "generating"
    ? { done: review.job.done, reviewId: review.id, total: review.job.total }
    : null;
}

function startDescription(isYear: boolean, ongoing: boolean) {
  if (isYear)
    return "See how this year felt, what kept coming back, and your own words from it.";
  return ongoing
    ? "See how this Chapter has felt so far, what has kept coming back, and your own words from it."
    : "See how this Chapter felt, what kept coming back, and your own words from it.";
}

function Progress({ count, job }: { count: number; job: Job }) {
  return (
    <div aria-live="polite" className={styles.progress} role="status">
      <p>
        Reading {plural(count, "Entry", "Entries")}. This can take a minute or
        two, and you can leave this page.
      </p>
      {job.total > 1 ? (
        <p className={styles.muted}>
          Part {Math.min(job.done + 1, job.total)} of {job.total}
        </p>
      ) : null}
      <div aria-hidden="true" className={styles.skeletons}>
        <Skeleton shape="block" />
        <Skeleton shape="line" width="80%" />
        <Skeleton shape="line" width="60%" />
      </div>
    </div>
  );
}

function ReadyHeader({
  busy,
  headingId,
  onDelete,
  onNew,
  review,
  timezone,
  title,
}: {
  busy: boolean;
  headingId: string;
  onDelete: () => void;
  onNew: (() => void) | null;
  review: StoredReview;
  timezone: string;
  title: string;
}) {
  const made = review.generatedAt
    ? new Intl.DateTimeFormat("en-US", {
        dateStyle: "medium",
        timeZone: validTimezone(timezone) ? timezone : "UTC",
      }).format(new Date(review.generatedAt))
    : null;
  const read =
    review.entriesRead === review.entriesInPeriod
      ? `Read all ${plural(review.entriesInPeriod, "Entry", "Entries")}`
      : `Read ${review.entriesRead} of ${review.entriesInPeriod} Entries`;
  return (
    <div className={styles.readyHeader}>
      <SectionHeader
        action={
          <span className={styles.actions}>
            {onNew ? (
              <Button
                disabled={busy}
                onClick={onNew}
                size="small"
                variant="secondary"
              >
                Make a new review
              </Button>
            ) : null}
            <Button
              disabled={busy}
              onClick={onDelete}
              size="small"
              variant="ghost"
            >
              Delete review
            </Button>
          </span>
        }
        detail={<Badge tone="outline">Written by AI</Badge>}
        headingId={headingId}
        title={title}
      />
      <p className={styles.meta}>
        <SeparatedList>
          {made ? <span>Made {made}</span> : null}
          <span>{read}</span>
        </SeparatedList>
      </p>
    </div>
  );
}

function ReadyBody({
  data,
  isYear,
  onNew,
  review,
  spanLabel,
  subject,
}: {
  data: ReviewPageData;
  isYear: boolean;
  onNew: (() => void) | null;
  review: StoredReview;
  spanLabel?: string;
  subject: ReviewSubjectProp;
}) {
  const content = review.content!;
  const noun = isYear ? "this year" : "this Chapter";
  const sources = useMemo(
    () => new Map(review.sources.map((source) => [source.id, source])),
    [review.sources],
  );
  const visible = (ids: readonly string[]) =>
    ids.flatMap((id) => {
      const source = sources.get(id);
      return source && !source.trashed ? [source] : [];
    });

  const phases = content.feelings.phases.flatMap((phase) => {
    const cited = visible(phase.entryIds);
    return cited.length > 0 ? [{ ...phase, cited }] : [];
  });
  const withYears = phasesSpanYears(content.feelings.phases);
  const themes = content.themes.flatMap((theme) => {
    const cited = visible(theme.entryIds);
    return cited.length > 0 ? [{ ...theme, cited }] : [];
  });
  const quotes = content.quotes.flatMap((quote, index) => {
    const source = sources.get(quote.entryId);
    return review.quoteAvailable[index] === true && source && !source.trashed
      ? [{ ...quote, source }]
      : [];
  });
  const hidden = content.quotes.length - quotes.length;

  const changed = review.changes.newEntries + review.changes.editedEntries;
  const trimmed =
    review.entriesRead < review.entriesInPeriod || review.trimmedEntries > 0;

  return (
    <div className={styles.body}>
      {changed > 0 && onNew ? (
        <p className={styles.notice}>
          <span>
            {plural(changed, "Entry", "Entries")} in {noun}{" "}
            {changed === 1 ? "is" : "are"} new or changed since this review.
          </span>
          <Button onClick={onNew} size="small" variant="ghost">
            Make a new review
          </Button>
        </p>
      ) : null}
      {review.changes.trashedEntries > 0 ? (
        <p className={styles.notice}>
          <span>
            {plural(review.changes.trashedEntries, "Entry", "Entries")} this
            review read {review.changes.trashedEntries === 1 ? "is" : "are"} in
            Trash, so what came from{" "}
            {review.changes.trashedEntries === 1 ? "it is" : "them is"} hidden.
            Restore {review.changes.trashedEntries === 1 ? "it" : "them"}, or
            make a new review without{" "}
            {review.changes.trashedEntries === 1 ? "it" : "them"}.
          </span>
        </p>
      ) : null}
      {trimmed ? (
        <p className={styles.notice}>
          <span>{trimmedNotice(review, isYear)}</span>
        </p>
      ) : null}

      <Records data={data} spanLabel={spanLabel} subject={subject} />

      <div lang={review.language}>
        <section
          aria-labelledby="review-felt"
          className={styles.interpretation}
        >
          <div className={styles.interpretationHeader}>
            <h3 id="review-felt">How it felt</h3>
            <Badge tone="warm">Interpretation</Badge>
          </div>
          {content.feelings.overview ? (
            <p>{content.feelings.overview}</p>
          ) : null}
          {phases.length > 0 ? (
            <ol className={styles.phases}>
              {phases.map((phase, index) => (
                <li key={`${phase.windowStart}-${index}`}>
                  <p className={styles.range}>
                    {phaseRangeLabel(
                      phase.windowStart,
                      phase.windowEnd,
                      withYears,
                    )}
                  </p>
                  <h4>{phase.feeling}</h4>
                  <p>{phase.description}</p>
                  <Citations entries={phase.cited} />
                </li>
              ))}
            </ol>
          ) : null}
        </section>

        {themes.length > 0 ? (
          <section
            aria-labelledby="review-themes"
            className={styles.interpretation}
          >
            <div className={styles.interpretationHeader}>
              <h3 id="review-themes">What kept coming back</h3>
              <Badge tone="warm">Interpretation</Badge>
            </div>
            <ul className={styles.themes}>
              {themes.map((theme, index) => (
                <li key={`${theme.name}-${index}`}>
                  <h4>{theme.name}</h4>
                  <p>{theme.description}</p>
                  <Citations entries={theme.cited} />
                </li>
              ))}
            </ul>
          </section>
        ) : null}

        {quotes.length > 0 || hidden > 0 ? (
          <section aria-labelledby="review-words" className={styles.words}>
            <div className={styles.interpretationHeader}>
              <h3 id="review-words">In your words</h3>
            </div>
            {quotes.map((quote, index) => (
              <figure
                className={styles.quote}
                key={`${quote.entryId}-${quote.start}-${index}`}
              >
                <blockquote>{quote.text}</blockquote>
                <figcaption>
                  <EntryLink entry={quote.source} />
                  <span className={styles.why}>
                    Why it stands out: {quote.why}
                  </span>
                </figcaption>
              </figure>
            ))}
            {hidden > 0 ? (
              <p className={styles.muted}>
                {hidden === 1
                  ? "1 quote is hidden because its Entry was edited or moved to Trash."
                  : `${hidden} quotes are hidden because their Entries were edited or moved to Trash.`}
              </p>
            ) : null}
          </section>
        ) : null}
      </div>

      <p className={styles.footer}>{REVIEW_FOOTER}</p>
    </div>
  );
}

function trimmedNotice(review: StoredReview, isYear: boolean) {
  const sampled = review.entriesRead < review.entriesInPeriod;
  const longer = review.trimmedEntries > 0;
  const lead = `${isYear ? "This year" : "This Chapter"} holds more writing than one review reads.`;
  if (sampled && longer)
    return `${lead} This review read ${review.entriesRead} of ${review.entriesInPeriod} Entries, spread evenly across the period, and the first 6,000 characters of longer ones.`;
  if (sampled)
    return `${lead} This review read ${review.entriesRead} of ${review.entriesInPeriod} Entries, spread evenly across the period.`;
  return `${lead} This review read the first 6,000 characters of longer Entries.`;
}

function EntryLink({ entry }: { entry: ReviewEntryRef }) {
  const occurrence = occurrenceOf(entry);
  const title = entry.title.trim();
  return (
    <Link className={styles.entryLink} href={`/items/${entry.id}`}>
      <span>{occurrenceLabel(occurrence)}</span>
      {title ? <span>{entryDisplayTitle(entry.title, occurrence)}</span> : null}
    </Link>
  );
}

function Citations({ entries }: { entries: readonly ReviewEntryRef[] }) {
  return (
    <details className={styles.citations}>
      <summary>From {plural(entries.length, "Entry", "Entries")}</summary>
      <ul>
        {entries.map((entry) => (
          <li key={entry.id}>
            <EntryLink entry={entry} />
          </li>
        ))}
      </ul>
    </details>
  );
}

function libraryHref(filters: {
  tag?: string;
  from?: string | null;
  to?: string | null;
}) {
  const parameters = new URLSearchParams();
  if (filters.tag) parameters.set("tag", filters.tag);
  if (filters.from) parameters.set("from", filters.from.slice(0, 10));
  if (filters.to) parameters.set("to", filters.to.slice(0, 10));
  const query = parameters.toString();
  return query ? `/library?${query}` : "/library";
}

function Records({
  data,
  spanLabel,
  subject,
}: {
  data: ReviewPageData;
  spanLabel?: string;
  subject: ReviewSubjectProp;
}) {
  const facts = data.facts;
  if (!facts) return null;
  const from =
    subject.scope === "year" ? `${subject.year}-01-01` : facts.firstDay;
  const to = subject.scope === "year" ? `${subject.year}-12-31` : facts.lastDay;
  const stats: ReactNode[] = [
    <span key="count">{plural(facts.entryCount, "Entry", "Entries")}</span>,
    subject.scope === "year" ? (
      <span key="span">{subject.year}</span>
    ) : spanLabel ? (
      <span key="span">{spanLabel}</span>
    ) : null,
    facts.firstTimes.length > 0 ? (
      <span key="firsts">
        {plural(facts.firstTimes.length, "First Time", "First Times")}
      </span>
    ) : null,
  ].filter(Boolean);
  return (
    <section aria-labelledby="review-records" className={styles.records}>
      <div className={styles.interpretationHeader}>
        <h3 id="review-records">From your records</h3>
      </div>
      <p className={styles.meta}>
        <SeparatedList>{stats}</SeparatedList>
      </p>
      {facts.topTags.length > 0 ? (
        <ul aria-label="Most used tags" className={styles.tags}>
          {facts.topTags.map((tag) => (
            <li key={tag.name}>
              <Link href={libraryHref({ from, tag: tag.name, to })}>
                <Badge tone="neutral">
                  {tag.name} {tag.count}
                </Badge>
              </Link>
            </li>
          ))}
        </ul>
      ) : null}
      {facts.firstTimes.length > 0 ? (
        <div>
          <p className={styles.label}>First Times</p>
          <ul className={styles.plainList}>
            {facts.firstTimes.map((entry) => (
              <li key={entry.id}>
                <EntryLink entry={entry} />
              </li>
            ))}
          </ul>
        </div>
      ) : null}
      {facts.busiestMonth ? (
        <p>
          Most writing: {monthLabel(facts.busiestMonth.month)} (
          {plural(facts.busiestMonth.count, "Entry", "Entries")})
        </p>
      ) : null}
      {subject.scope === "year" && facts.chapters.length > 0 ? (
        <div>
          <p className={styles.label}>Chapters during {subject.year}</p>
          <ul className={styles.plainList}>
            {facts.chapters.map((chapter) => (
              <li key={chapter.id}>
                <Link
                  className={styles.entryLink}
                  href={`/items/${chapter.id}`}
                >
                  <span>{chapter.title || "Untitled Chapter"}</span>
                  <span>{occurrenceSpanLabel(occurrenceOf(chapter))}</span>
                </Link>
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </section>
  );
}
