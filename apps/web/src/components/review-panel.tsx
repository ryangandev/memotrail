"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useId, useMemo, useState, type ReactNode } from "react";
import { saveReviewPreferences } from "@/app/reviews/actions";
import { notify } from "@/components/app-toast";
import { Badge } from "@/components/badge";
import { Button } from "@/components/button";
import { useConfirmationDialog } from "@/components/confirmation-dialog";
import { EntryRow, EntryRowList } from "@/components/entry-row";
import { Icon } from "@/components/icon";
import { ReviewDisclosureDialog } from "@/components/review-disclosure-dialog";
import styles from "@/components/review-panel.module.css";
import { SeparatedList } from "@/components/separated-list";
import { Skeleton } from "@/components/skeleton";
import {
  chapterSendsLine,
  REVIEW_DISCLOSURE_VERSION,
  REVIEW_FOOTER,
  yearSendsLine,
} from "@/lib/ai/review-disclosure";
import { entryRowDate, entryRowLabels } from "@/lib/data/entry-row";
import {
  entryDisplayTitle,
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
 * The line that says what a finished review is: how many Entries it read, that Claude wrote it,
 * and when. A year page shows it under its title; a Chapter shows it beside "Looking back".
 */
export function ReviewMeta({
  badge = true,
  chapterCount = 0,
  review,
  timezone,
}: {
  badge?: boolean;
  /** The Chapters a year review also read, by name and dates. */
  chapterCount?: number;
  review: StoredReview;
  timezone: string;
}) {
  const made = review.generatedAt
    ? new Intl.DateTimeFormat("en-US", {
        dateStyle: "long",
        timeZone: validTimezone(timezone) ? timezone : "UTC",
      }).format(new Date(review.generatedAt))
    : null;
  const entries =
    review.entriesRead === review.entriesInPeriod
      ? plural(review.entriesInPeriod, "Entry", "Entries")
      : `${review.entriesRead} of ${review.entriesInPeriod} Entries`;
  const chapters =
    chapterCount > 0
      ? ` and ${plural(chapterCount, "Chapter", "Chapters")}`
      : "";
  return (
    <SeparatedList className={styles.metaList}>
      <span>
        {review.ongoing ? "So far, from" : "From"} {entries}
        {chapters}
      </span>
      {badge ? <AiBadge /> : null}
      {made ? <span>{made}</span> : null}
    </SeparatedList>
  );
}

function AiBadge() {
  return (
    <Badge className={styles.aiBadge} size="medium" tone="neutral">
      Written by AI
    </Badge>
  );
}

/**
 * A review of a Chapter or a year: Claude's reading of how it felt and what kept coming up, the
 * person's own words, quoted exactly, and facts counted from their records. A review is made only
 * when the person asks, it is labeled as written by AI, and everything on it links back to the
 * Entries it came from. A year page carries the review's title and meta line in its own header;
 * a Chapter's review heads itself "Looking back".
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
  /** The Chapter's dates, such as "Mar 2026 - May 2026", for the facts line. */
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
          The review is deleted. Your Entries are not changed, and you can write
          a new review later.
        </>
      ),
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
      aria-label={isYear ? `${subject.year} review` : undefined}
      aria-labelledby={isYear ? undefined : "review-heading"}
      className={styles.panel}
      data-scope={subject.scope}
      data-ui-review-panel
    >
      {isYear ? null : (
        <div className={styles.head}>
          <h2 className={styles.headTitle} id="review-heading">
            Looking back
          </h2>
          {hasContent && review ? (
            <>
              <AiBadge />
              <span className={styles.headMeta}>
                <ReviewMeta badge={false} review={review} timezone={timezone} />
              </span>
            </>
          ) : null}
        </div>
      )}

      {failureText ? (
        <div className={styles.failure} role="alert">
          <p>{failureText}</p>
          {canRetry ? (
            <Button
              disabled={actionBusy}
              loading={starting}
              onClick={begin}
              size="small"
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
          <p className={styles.lead}>{startDescription(isYear, ongoing)}</p>
          <p className={styles.sends}>
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
            onNew={eligible && !job ? begin : null}
            review={review}
            spanLabel={spanLabel}
            subject={subject}
          />
          <p className={styles.footer}>{REVIEW_FOOTER}</p>
          <div className={styles.actions}>
            {eligible ? (
              <Button
                disabled={actionBusy}
                loading={starting}
                onClick={begin}
                size="small"
                variant="quiet"
              >
                Write again
              </Button>
            ) : null}
            <Button
              className={styles.delete}
              disabled={actionBusy}
              onClick={() => void remove()}
              size="small"
              variant="danger"
            >
              Delete review
            </Button>
          </div>
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
    return "See how this year felt, what kept coming up, and your own words from it.";
  return ongoing
    ? "See how this Chapter has felt so far, what has kept coming up, and your own words from it."
    : "See how this Chapter felt, what kept coming up, and your own words from it.";
}

function Progress({ count, job }: { count: number; job: Job }) {
  return (
    <div aria-live="polite" className={styles.progress} role="status">
      <p>
        Reading {plural(count, "Entry", "Entries")}. This can take a minute or
        two, and you can leave this page.
      </p>
      {job.total > 1 ? (
        <p className={styles.part}>
          Part {Math.min(job.done + 1, job.total)} of {job.total}
        </p>
      ) : null}
      <div aria-hidden="true" className={styles.skeletons}>
        <Skeleton shape="line" width="92%" />
        <Skeleton shape="line" width="86%" />
        <Skeleton shape="line" width="60%" />
      </div>
    </div>
  );
}

function ReadyBody({
  data,
  onNew,
  review,
  spanLabel,
  subject,
}: {
  data: ReviewPageData;
  onNew: (() => void) | null;
  review: StoredReview;
  spanLabel?: string;
  subject: ReviewSubjectProp;
}) {
  const content = review.content!;
  const isYear = subject.scope === "year";
  const noun = isYear ? "this year" : "this Chapter";
  // A year's sections sit under the page title; a Chapter's under "Looking back".
  const Heading = isYear ? "h2" : "h3";
  const Subheading = isYear ? "h3" : "h4";
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
  const trashed = review.changes.trashedEntries;
  const trimmed =
    review.entriesRead < review.entriesInPeriod || review.trimmedEntries > 0;
  const notices: ReactNode[] = [];
  if (changed > 0 && onNew)
    notices.push(
      <p className={styles.notice} key="changed">
        <span>
          {plural(changed, "Entry", "Entries")} in {noun}{" "}
          {changed === 1 ? "is" : "are"} new or changed since this review.
        </span>{" "}
        <button className={styles.inlineAction} onClick={onNew} type="button">
          Write again
        </button>
      </p>,
    );
  if (trashed > 0)
    notices.push(
      <p className={styles.notice} key="trashed">
        {plural(trashed, "Entry", "Entries")} this review read{" "}
        {trashed === 1 ? "is" : "are"} in Trash, so what came from{" "}
        {trashed === 1 ? "it is" : "them is"} hidden. Restore{" "}
        {trashed === 1 ? "it" : "them"}, or write the review again without{" "}
        {trashed === 1 ? "it" : "them"}.
      </p>,
    );
  if (trimmed)
    notices.push(
      <p className={styles.notice} key="trimmed">
        {trimmedNotice(review, isYear)}
      </p>,
    );

  return (
    <div className={styles.body}>
      {notices.length > 0 ? (
        <div className={styles.notices}>{notices}</div>
      ) : null}

      <div className={styles.interpretation} lang={review.language}>
        <section aria-labelledby="review-felt" className={styles.section}>
          <Heading className={styles.sectionTitle} id="review-felt">
            How it felt
          </Heading>
          <div className={styles.prose}>
            {content.feelings.overview ? (
              <p>{content.feelings.overview}</p>
            ) : null}
            {phases.map((phase, index) => (
              <Phase
                cited={phase.cited}
                description={phase.description}
                feeling={phase.feeling}
                heading={Subheading}
                key={`${phase.windowStart}-${index}`}
                range={phaseRangeLabel(
                  phase.windowStart,
                  phase.windowEnd,
                  withYears,
                )}
              />
            ))}
          </div>
        </section>

        {themes.length > 0 ? (
          <section aria-labelledby="review-themes" className={styles.section}>
            <Heading className={styles.sectionTitle} id="review-themes">
              What kept coming up
            </Heading>
            <ul className={styles.themes}>
              {themes.map((theme, index) => (
                <Theme
                  cited={theme.cited}
                  description={theme.description}
                  heading={Subheading}
                  key={`${theme.name}-${index}`}
                  name={theme.name}
                />
              ))}
            </ul>
          </section>
        ) : null}

        {quotes.length > 0 || hidden > 0 ? (
          <section aria-labelledby="review-words" className={styles.section}>
            <Heading className={styles.sectionTitle} id="review-words">
              In your words
            </Heading>
            {quotes.map((quote, index) => (
              <figure
                className={styles.quote}
                key={`${quote.entryId}-${quote.start}-${index}`}
              >
                <blockquote>{quote.text}</blockquote>
                <figcaption>
                  <QuoteSource entry={quote.source} />
                  <span className={styles.why}>
                    Why it stands out: {quote.why}
                  </span>
                </figcaption>
              </figure>
            ))}
            {hidden > 0 ? (
              <p className={styles.hidden}>
                {hidden === 1
                  ? "1 quote is hidden because its Entry was edited or moved to Trash."
                  : `${hidden} quotes are hidden because their Entries were edited or moved to Trash.`}
              </p>
            ) : null}
          </section>
        ) : null}
      </div>

      {subject.scope === "year" &&
      data.facts &&
      data.facts.chapters.length > 0 ? (
        <section aria-labelledby="review-chapters" className={styles.section}>
          <Heading className={styles.sectionTitle} id="review-chapters">
            Chapters during {subject.year}
          </Heading>
          <ul className={styles.rows}>
            {data.facts.chapters.map((chapter) => (
              <li key={chapter.id}>
                <FactRow
                  date={entryRowDate(occurrenceOf(chapter), {
                    isChapter: true,
                  })}
                  href={`/items/${chapter.id}`}
                  title={chapter.title || "Untitled Chapter"}
                />
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      <Records
        data={data}
        heading={Heading}
        spanLabel={spanLabel}
        subject={subject}
      />
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

/** The day an Entry stands for, at the precision it was recorded, always with its year. */
function entryDate(entry: ReviewEntryRef) {
  return entryRowDate(occurrenceOf(entry), { year: "show" });
}

/** A quote's source: the Entry's date, then its title when it has one of its own. */
function QuoteSource({ entry }: { entry: ReviewEntryRef }) {
  const title = entry.title.trim();
  return (
    <Link className={styles.source} href={`/items/${entry.id}`}>
      <span className={styles.sourceDate}>{entryDate(entry)}</span>
      {title ? (
        <span className={styles.sourceTitle}>
          {entryDisplayTitle(entry.title, occurrenceOf(entry))}
        </span>
      ) : null}
    </Link>
  );
}

/** Entries the review points to, drawn as every Entry list draws them. */
function EntryRows({
  entries,
  firstTimes = false,
  label,
}: {
  entries: readonly ReviewEntryRef[];
  firstTimes?: boolean;
  label?: string;
}) {
  return (
    <EntryRowList label={label}>
      {entries.map((entry) => {
        const labels = entryRowLabels({
          occurrence: occurrenceOf(entry),
          title: entry.title,
          year: "show",
        });
        return (
          <EntryRow
            date={labels.date}
            dateTime={labels.dateTime}
            href={`/items/${entry.id}`}
            isFirstTime={firstTimes}
            key={entry.id}
            title={labels.title}
            variant="compact"
          />
        );
      })}
    </EntryRowList>
  );
}

/** One quiet row: a serif name in ink and its dates in muted text, opening its page. */
function FactRow({
  date,
  href,
  title,
}: {
  date: string;
  href: string;
  title: string;
}) {
  return (
    <Link className={styles.row} href={href}>
      <span className={styles.rowTitle}>{title}</span>
      <span className={styles.rowDate}>{date}</span>
    </Link>
  );
}

/** The Entries a part of the review came from, shown when the person asks. */
function useCitations(entries: readonly ReviewEntryRef[]) {
  const [open, setOpen] = useState(false);
  const id = useId();
  const toggle = (label: ReactNode, className?: string) => (
    <button
      aria-controls={id}
      aria-expanded={open}
      className={[styles.cited, className].filter(Boolean).join(" ")}
      onClick={() => setOpen((value) => !value)}
      type="button"
    >
      {label}
      <Icon name="chevronDown" size={14} />
    </button>
  );
  const list = open ? (
    <div className={styles.citations} id={id}>
      <EntryRows entries={entries} />
    </div>
  ) : null;
  return { list, toggle };
}

function Phase({
  cited,
  description,
  feeling,
  heading: Heading,
  range,
}: {
  cited: readonly ReviewEntryRef[];
  description: string;
  feeling: string;
  heading: "h3" | "h4";
  range: string;
}) {
  const { list, toggle } = useCitations(cited);
  return (
    <div className={styles.phase}>
      <Heading className={styles.phaseTitle}>{feeling}</Heading>
      <p>{description}</p>
      <p className={styles.phaseMeta}>
        <SeparatedList>
          <span>{range}</span>
          {toggle(`From ${plural(cited.length, "Entry", "Entries")}`)}
        </SeparatedList>
      </p>
      {list}
    </div>
  );
}

function Theme({
  cited,
  description,
  heading: Heading,
  name,
}: {
  cited: readonly ReviewEntryRef[];
  description: string;
  heading: "h3" | "h4";
  name: string;
}) {
  const { list, toggle } = useCitations(cited);
  return (
    <li className={styles.theme}>
      <Heading className={styles.themeName}>{name}</Heading>
      {toggle(plural(cited.length, "Entry", "Entries"), styles.themeCount)}
      <p className={styles.themeText}>{description}</p>
      {list}
    </li>
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

/** Facts counted from the person's own Entries, not written by Claude. */
function Records({
  data,
  heading: Heading,
  spanLabel,
  subject,
}: {
  data: ReviewPageData;
  heading: "h2" | "h3";
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
    subject.scope === "chapter" && spanLabel ? (
      <span key="span">{spanLabel}</span>
    ) : null,
    facts.firstTimes.length > 0 ? (
      <span key="firsts">
        {plural(facts.firstTimes.length, "First Time", "First Times")}
      </span>
    ) : null,
    facts.busiestMonth ? (
      <span key="busiest">
        Most writing in {monthLabel(facts.busiestMonth.month)} (
        {plural(facts.busiestMonth.count, "Entry", "Entries")})
      </span>
    ) : null,
  ].filter(Boolean);
  return (
    <section aria-labelledby="review-records" className={styles.section}>
      <Heading className={styles.sectionTitle} id="review-records">
        From your records
      </Heading>
      <p className={styles.facts}>
        <SeparatedList>{stats}</SeparatedList>
      </p>
      {facts.topTags.length > 0 ? (
        <ul aria-label="Most used tags" className={styles.tags}>
          {facts.topTags.map((tag) => (
            <li key={tag.name}>
              <Link href={libraryHref({ from, tag: tag.name, to })}>
                #{tag.name} <span>{tag.count}</span>
              </Link>
            </li>
          ))}
        </ul>
      ) : null}
      {facts.firstTimes.length > 0 ? (
        <div className={styles.group}>
          <p aria-hidden="true" className={styles.groupLabel}>
            First Times
          </p>
          <EntryRows
            entries={facts.firstTimes}
            firstTimes
            label="First Times"
          />
        </div>
      ) : null}
    </section>
  );
}
