"use client";

import dynamic from "next/dynamic";
import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import {
  confirmChapterSuggestion,
  dismissChapterSuggestion,
} from "@/app/reviews/actions";
import { notify } from "@/components/app-toast";
import { Badge } from "@/components/badge";
import { Button } from "@/components/button";
import styles from "@/components/chapter-suggestion-card.module.css";
import { EntryRow, EntryRowList } from "@/components/entry-row";
import { SeparatedList } from "@/components/separated-list";
import { entryRowDate, entryRowLabels } from "@/lib/data/entry-row";
import { validTimezone } from "@/lib/data/occurrence";
import {
  suggestionOccurrenceDraft,
  type ChapterSuggestion,
} from "@/lib/data/review-input";

const NewEntryDialog = dynamic(
  () =>
    import("@/components/entry-editor-dialog").then(
      (module) => module.NewEntryDialog,
    ),
  { loading: () => null },
);

const PREVIEW_COUNT = 3;

/** The suggested span the way a Chapter row reads it, such as "Jun 2026 - now". */
function suggestionSpan(suggestion: ChapterSuggestion) {
  return entryRowDate(
    {
      datePrecision: suggestion.startPrecision,
      occurredAt: `${suggestion.startDate}T12:00:00Z`,
      occurredEnd: suggestion.endDate
        ? `${suggestion.endDate}T12:00:00Z`
        : null,
      occurredLabel: null,
      occurredTimezone: "UTC",
    },
    { isChapter: true },
  );
}

/**
 * A quiet suggestion that a stretch of writing may be a Chapter. Nothing is created until the
 * person reviews the proposed Chapter and saves it; dismissing keeps only its dates, so the same
 * stretch is not suggested again. It sits between hairlines like any other row of the page, with
 * the "Suggested by AI" badge marking what Claude proposed.
 */
export function ChapterSuggestionCard({
  ownerId,
  suggestion,
  tagOptions,
  timezone,
}: {
  ownerId: string;
  suggestion: ChapterSuggestion;
  tagOptions: string[];
  timezone: string;
}) {
  const router = useRouter();
  const [editing, setEditing] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [gone, setGone] = useState(false);
  const [busy, setBusy] = useState(false);
  const draft = useMemo(
    () => ({
      occurrence: suggestionOccurrenceDraft(
        suggestion,
        validTimezone(timezone) ? timezone : "UTC",
      ),
      title: suggestion.name,
    }),
    [suggestion, timezone],
  );
  if (gone) return null;

  const shown = expanded
    ? suggestion.entries
    : suggestion.entries.slice(0, PREVIEW_COUNT);
  const more = suggestion.entries.length - shown.length;

  async function dismiss() {
    if (busy) return;
    setBusy(true);
    try {
      if (!(await dismissChapterSuggestion(suggestion.id))) throw Error();
      setGone(true);
      notify.info("This suggestion won't come back.");
      router.refresh();
    } catch {
      notify.error("MemoTrail could not dismiss this suggestion. Try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <section aria-labelledby="chapter-suggestion-title" className={styles.card}>
      <div className={styles.kind}>
        <svg aria-hidden="true" className={styles.mark} viewBox="0 0 24 24">
          <path
            d="M5 6v12M19 6v12M5 12h14"
            fill="none"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="1.8"
          />
        </svg>
        <p>Suggested Chapter</p>
        <Badge className={styles.badge} size="medium" tone="neutral">
          Suggested by AI
        </Badge>
      </div>
      <h2 id="chapter-suggestion-title">{suggestion.name}</h2>
      <p className={styles.facts}>
        <SeparatedList>
          <span>{suggestionSpan(suggestion)}</span>
          <span>
            Based on {suggestion.entryCount}{" "}
            {suggestion.entryCount === 1 ? "Entry" : "Entries"}
          </span>
        </SeparatedList>
      </p>
      <p className={styles.rationale}>{suggestion.rationale}</p>
      {shown.length > 0 ? (
        <div className={styles.entries}>
          <EntryRowList label="Entries this suggestion is based on">
            {shown.map((entry) => {
              const labels = entryRowLabels({
                occurrence: {
                  datePrecision: entry.datePrecision,
                  occurredAt: entry.occurredStart,
                  occurredEnd: entry.occurredEnd,
                  occurredLabel: entry.occurredLabel,
                  occurredTimezone: validTimezone(entry.occurredTimezone)
                    ? entry.occurredTimezone
                    : "UTC",
                },
                title: entry.title,
                year: "show",
              });
              return (
                <EntryRow
                  date={labels.date}
                  dateTime={labels.dateTime}
                  href={`/items/${entry.id}`}
                  key={entry.id}
                  title={labels.title}
                  variant="compact"
                />
              );
            })}
          </EntryRowList>
          {more > 0 ? (
            <button
              className={styles.more}
              onClick={() => setExpanded(true)}
              type="button"
            >
              Show all {suggestion.entries.length}
            </button>
          ) : null}
        </div>
      ) : null}
      <div className={styles.actions}>
        <Button
          disabled={busy}
          onClick={() => setEditing(true)}
          variant="secondary"
        >
          Review and add
        </Button>
        <Button
          disabled={busy}
          loading={busy}
          onClick={() => void dismiss()}
          variant="quiet"
        >
          Dismiss
        </Button>
      </div>
      {editing ? (
        <NewEntryDialog
          initialDraft={draft}
          marks={{ isChapter: true, isFirstTime: false }}
          onClose={() => setEditing(false)}
          onSaved={(saved) => {
            setGone(true);
            void confirmChapterSuggestion(suggestion.id, saved.id).then(
              () => router.refresh(),
              () => undefined,
            );
          }}
          ownerId={ownerId}
          tagOptions={tagOptions}
          timezone={timezone}
        />
      ) : null}
    </section>
  );
}
