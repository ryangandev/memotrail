"use client";

import dynamic from "next/dynamic";
import Link from "next/link";
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
import { SeparatedList } from "@/components/separated-list";
import {
  entryDisplayTitle,
  occurrenceLabel,
  validTimezone,
} from "@/lib/data/occurrence";
import {
  suggestionOccurrenceDraft,
  suggestionSpanLabel,
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

/**
 * A quiet suggestion that a stretch of writing may be a Chapter. Nothing is created until the
 * person reviews the proposed Chapter and saves it; dismissing keeps only its dates, so the same
 * stretch is not suggested again.
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
      <div className={styles.eyebrow}>
        <p>Suggested Chapter</p>
        <Badge tone="warm">Suggested by AI</Badge>
      </div>
      <h2 id="chapter-suggestion-title">{suggestion.name}</h2>
      <p className={styles.facts}>
        <SeparatedList>
          <span>{suggestionSpanLabel(suggestion)}</span>
          <span>
            Based on {suggestion.entryCount}{" "}
            {suggestion.entryCount === 1 ? "Entry" : "Entries"}
          </span>
        </SeparatedList>
      </p>
      <div className={styles.rationale}>
        <p>{suggestion.rationale}</p>
        {shown.length > 0 ? (
          <ul aria-label="Entries this suggestion is based on">
            {shown.map((entry) => {
              const occurrence = {
                datePrecision: entry.datePrecision,
                occurredAt: entry.occurredStart,
                occurredEnd: entry.occurredEnd,
                occurredLabel: entry.occurredLabel,
                occurredTimezone: validTimezone(entry.occurredTimezone)
                  ? entry.occurredTimezone
                  : "UTC",
              };
              return (
                <li key={entry.id}>
                  <Link href={`/items/${entry.id}`}>
                    <span>{occurrenceLabel(occurrence)}</span>
                    {entry.title.trim() ? (
                      <span>{entryDisplayTitle(entry.title, occurrence)}</span>
                    ) : null}
                  </Link>
                </li>
              );
            })}
          </ul>
        ) : null}
        {!expanded && suggestion.entries.length > PREVIEW_COUNT ? (
          <Button
            onClick={() => setExpanded(true)}
            size="small"
            variant="ghost"
          >
            Show all {suggestion.entries.length}
          </Button>
        ) : null}
      </div>
      <div className={styles.actions}>
        <Button
          disabled={busy}
          onClick={() => setEditing(true)}
          variant="primary"
        >
          Review and add
        </Button>
        <Button
          disabled={busy}
          loading={busy}
          onClick={() => void dismiss()}
          variant="ghost"
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
