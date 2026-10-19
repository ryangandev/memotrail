"use client";
import { notify } from "@/components/app-toast";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/button";
import { useConfirmationDialog } from "@/components/confirmation-dialog";
import Link from "next/link";
import { useId, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { EntryEditorDialog } from "./entry-editor-dialog";
import { Icon } from "./icon";
import { EntryPhotos } from "./entry-photos";
import { EntryRichTextContent } from "./entry-rich-text-content";
import { EntryRow, EntryRowList } from "./entry-row";
import { ReviewPanel } from "./review-panel";
import { SectionHeader } from "./section-header";
import { SeparatedList } from "./separated-list";
import { PageBackLink } from "./workspace-destination";
import { loadEditableEntry, trashWikiItem } from "@/app/items/actions";
import {
  chapterDateFacts,
  chapterSpanLabel,
  entryDateAddsToTitle,
  entryDateLabel,
  entryTitle,
  type EntryDetail,
} from "@/lib/data/entry-detail";
import type { EntryChapter } from "@/lib/data/entry-chapters";
import {
  chapterEntriesPageSize,
  type ChapterContents,
} from "@/lib/data/chapter-contents-types";
import {
  occurrenceSpanLabel,
  storedOccurrence,
  type Occurrence,
} from "@/lib/data/occurrence";
import {
  chapterRelation,
  occurrenceWindow,
} from "@/lib/data/occurrence-window";
import {
  entryRowDate,
  entryRowDateTime,
  entryRowLabels,
} from "@/lib/data/entry-row";
import { wikiEntryHref, wikiItemSubtypeLabel } from "@/lib/data/wiki-item";
import { destinationForEntry } from "@/lib/workspace-destinations";
import type { EntryPhotos as EntryPhotoList } from "@/lib/data/entry-photos";
import type { ReviewPageData, ReviewSettings } from "@/lib/data/review-input";
import { locationDisplayLabel } from "@/lib/locations/location";
import styles from "@/components/entry-detail-view.module.css";

/** What a Chapter's Item page adds: the Entries dated inside it and the Chapters beside it. */
export type ChapterPageData = {
  /** Null for a Chapter without a calendar date, which has no days to hold Entries. */
  contents: ChapterContents | null;
  /** The request date as an ISO string, so server and client render the same duration. */
  now: string;
  page: number;
  /** True when the address asks for every Entry, page by page, rather than the first few. */
  showAll: boolean;
  /** The Chapter's review, or null when reviews could not be read. */
  review: {
    data: ReviewPageData;
    preferences: ReviewSettings;
    timezone: string;
    today: string;
  } | null;
};

/** How many Entries a Chapter's page lists before "Show all". */
const chapterPreviewCount = 5;

const sourceLinkLabels: Record<string, string> = {
  exploration_source: "Open source Entry",
  exploration_conclusion: "Open saved conclusion",
};

export function EntryDetailView({
  chapter = null,
  chapters = null,
  entry,
  ownerId,
  photos,
}: {
  chapter?: ChapterPageData | null;
  /** The Chapters an Entry falls inside, innermost first, or null when they could not be read. */
  chapters?: EntryChapter[] | null;
  entry: EntryDetail;
  ownerId: string;
  // Null when the item is in Trash or its photos could not load.
  photos: EntryPhotoList | null;
}) {
  const router = useRouter();
  const requestConfirmation = useConfirmationDialog();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] =
    useState<Awaited<ReturnType<typeof loadEditableEntry>>>(null);
  const active = !entry.deleted_at;
  const kind = wikiItemSubtypeLabel(entry.item_subtype);
  const editable = active && entry.item_kind === "entry";

  async function edit() {
    setBusy(true);
    setError(null);
    try {
      const data = await loadEditableEntry(entry.id);
      if (!data) throw Error();
      setEditing(data);
    } catch {
      setError(
        `This ${kind} cannot be edited right now. Refresh and try again.`,
      );
    } finally {
      setBusy(false);
    }
  }
  async function moveToTrash() {
    if (busy) return;
    const confirmed = await requestConfirmation({
      title: <>Move “{entryTitle(entry)}” to Trash?</>,
      description: <>You can restore it later from Trash.</>,
      confirmLabel: "Move to Trash",
      variant: "danger",
    });
    if (!confirmed) return;

    setBusy(true);
    setError(null);
    try {
      const message = await trashWikiItem(entry.id, entry.revision);
      if (message) setError(message);
      else {
        router.push("/library");
        router.refresh();
        notify.info(`${kind} moved to Trash.`);
      }
    } catch {
      setError(
        "Could not confirm the move to Trash. Refresh before trying again.",
      );
    } finally {
      setBusy(false);
    }
  }

  const editButton = editable ? (
    <Button
      // The visible "Edit" reads with the page; the name says what it edits.
      aria-label={chapter ? undefined : `Edit ${kind}`}
      disabled={busy}
      onClick={() => void edit()}
      type="button"
      variant="secondary"
    >
      {chapter ? `Edit ${kind}` : "Edit"}
    </Button>
  ) : null;
  const trashButton = active ? (
    <Button
      disabled={busy}
      onClick={() => void moveToTrash()}
      type="button"
      variant="danger"
    >
      Move to Trash
    </Button>
  ) : null;
  const actions =
    editButton || trashButton ? (
      <div className={styles.actions} data-entry-actions>
        {editButton}
        {trashButton ? (
          <span className={styles.trash}>{trashButton}</span>
        ) : null}
      </div>
    ) : null;
  const editor = editing ? (
    <EntryEditorDialog
      defaultTimezone={editing.defaultTimezone}
      entry={editing.entry}
      ownerId={ownerId}
      photos={editing.photos}
      tagOptions={editing.tagOptions}
      onClose={() => setEditing(null)}
      // The editor refreshes the page after it saves.
      onSaved={() => setEditing(null)}
    />
  ) : null;
  const alert = error ? (
    <p className={styles.alert} role="alert">
      {error}
    </p>
  ) : null;
  const trashNotice = active ? null : (
    <p className={styles.trashNotice} role="status">
      This {kind} is in Trash. <Link href="/trash">Restore it from Trash</Link>{" "}
      to change it.
    </p>
  );
  const firstTime = entry.is_first_time ? <FirstTimeMark /> : null;
  const shownPhotos = active ? photos : { hasMore: false, photos: [] };

  if (chapter) {
    return (
      <article aria-label={kind} className={styles.chapter}>
        <ChapterHeader chapter={chapter} entry={entry} />
        {firstTime}
        {trashNotice}
        {entry.body ? (
          <EntryRichTextContent
            body={entry.body}
            className={`${styles.description} ${styles.reading}`}
            metadata={entry.metadata}
          />
        ) : null}
        <ChapterSpanBar entry={entry} now={new Date(chapter.now)} />
        <div className={styles.headActions}>
          {editButton}
          {trashButton ? (
            <span className={styles.trash}>{trashButton}</span>
          ) : null}
        </div>
        {alert}
        <SourceLinks entry={entry} />
        <div className={styles.reading}>
          <Photos photos={shownPhotos} />
        </div>
        <ChapterSections
          chapter={chapter}
          entry={entry}
          onEdit={() => void edit()}
        />
        {editor}
      </article>
    );
  }

  return (
    <article aria-label={kind} className={styles.entry}>
      <PageHeader
        back={destinationForEntry(entry)}
        meta={<EntryFacts entry={entry} />}
        title={<>{entryTitle(entry)}</>}
      />
      {firstTime}
      {trashNotice}
      <EntryRichTextContent
        body={entry.body || "No writing has been added yet."}
        className={entry.body ? styles.body : styles.bodyEmpty}
        metadata={entry.body ? entry.metadata : undefined}
      />
      <SourceLinks entry={entry} />
      <Photos photos={shownPhotos} />
      {chapters?.length ? <InChapter chapters={chapters} /> : null}
      {actions}
      {alert}
      {editor}
    </article>
  );
}

/** The facts line under an Entry's title: its date, places, and tags. */
function EntryFacts({ entry }: { entry: EntryDetail }) {
  const occurrence = occurrenceOf(entry);
  const facts: ReactNode[] = [];
  // An untitled Entry is already headed by its date.
  if (entryDateAddsToTitle(entry)) {
    facts.push(
      <time dateTime={entryRowDateTime(occurrence) ?? undefined} key="date">
        {entryDateLabel(entry)}
      </time>,
    );
  }
  for (const location of entry.locations) {
    facts.push(
      <span key={location.location_id}>
        {locationDisplayLabel({
          formattedAddress: location.formatted_address,
          latitude: location.latitude,
          longitude: location.longitude,
        })}
      </span>,
    );
  }
  if (entry.tags.length) facts.push(<TagLinks key="tags" tags={entry.tags} />);
  return facts.length ? (
    <SeparatedList className={styles.facts} data-entry-facts>
      {facts}
    </SeparatedList>
  ) : null;
}

function TagLinks({ tags }: { tags: EntryDetail["tags"] }) {
  return (
    <span className={styles.tags}>
      {tags.map((tag) => (
        <Link
          href={`/library?tag=${encodeURIComponent(tag.name)}`}
          key={tag.id}
        >
          #{tag.name}
        </Link>
      ))}
    </span>
  );
}

function FirstTimeMark() {
  return (
    <p className={styles.firstTime}>
      <Icon name="firstTime" size={13} />
      First Time
    </p>
  );
}

function SourceLinks({ entry }: { entry: EntryDetail }) {
  const links = entry.links.filter(
    (link) => sourceLinkLabels[link.relationship],
  );
  if (!links.length) return null;
  return (
    <p className={styles.sources}>
      {links.map((link) => (
        <Link
          href={`/items/${link.target_entry_id}`}
          key={`${link.relationship}:${link.target_entry_id}`}
        >
          {sourceLinkLabels[link.relationship]}
        </Link>
      ))}
    </p>
  );
}

function Photos({ photos }: { photos: EntryPhotoList | null }) {
  if (photos === null) {
    return (
      <p className={styles.photosError} role="alert">
        Photos could not load. Refresh the page to try again.
      </p>
    );
  }
  return photos.photos.length > 0 ? (
    <EntryPhotos hasMore={photos.hasMore} photos={photos.photos} />
  ) : null;
}

/** The Chapters an Entry falls inside, each on a row between rules. */
function InChapter({ chapters }: { chapters: EntryChapter[] }) {
  return (
    <ul aria-label="Chapters this Entry is in" className={styles.inChapter}>
      {chapters.map((chapter) => (
        <li key={chapter.id}>
          <span className={styles.chapterIcon}>
            <Icon name="chapter" size={16} />
          </span>
          <span className={styles.inChapterLabel}>In Chapter</span>
          <Link className={styles.inChapterTitle} href={wikiEntryHref(chapter)}>
            {chapter.title}
          </Link>
          <span className={styles.inChapterSpan}>
            {occurrenceSpanLabel(chapter.occurrence)}
          </span>
        </li>
      ))}
    </ul>
  );
}

/** A Chapter's title block: the back link, its kind, its title, and its span, length, and tags. */
function ChapterHeader({
  chapter,
  entry,
}: {
  chapter: ChapterPageData;
  entry: EntryDetail;
}) {
  const span = chapterSpanLabel(entry);
  const { duration } = chapterDateFacts(entry, new Date(chapter.now));
  const contents = chapter.contents;
  const total = contents && !contents.failed ? contents.totalCount : null;
  const meta: ReactNode[] = [];
  if (span) meta.push(<span key="span">{span}</span>);
  if (duration) meta.push(<span key="duration">{lowerFirst(duration)}</span>);
  if (total !== null) {
    meta.push(
      <span key="count">
        {total} {total === 1 ? "Entry" : "Entries"}
      </span>,
    );
  }
  for (const location of entry.locations) {
    meta.push(
      <span key={location.location_id}>
        {locationDisplayLabel({
          formattedAddress: location.formatted_address,
          latitude: location.latitude,
          longitude: location.longitude,
        })}
      </span>,
    );
  }
  if (entry.tags.length) meta.push(<TagLinks key="tags" tags={entry.tags} />);
  return (
    <header className={styles.chapterHeader} data-ui-page-header>
      <PageBackLink destination={destinationForEntry(entry)} />
      <p className={styles.kind}>
        <Icon name="chapter" size={15} />
        Chapter
      </p>
      <h1 className={styles.chapterTitle}>{entryTitle(entry)}</h1>
      {meta.length ? (
        <div className={styles.chapterMeta}>
          <SeparatedList className={styles.facts} data-entry-facts>
            {meta}
          </SeparatedList>
        </div>
      ) : null}
    </header>
  );
}

// "About 2 years" reads mid-line as "about 2 years".
function lowerFirst(value: string) {
  return value.charAt(0).toLowerCase() + value.slice(1);
}

/**
 * Where a Chapter sits in its years: a track from the January it began to the December it ended,
 * or the current one while it goes on, with the Chapter's own days filled in.
 */
function ChapterSpanBar({ entry, now }: { entry: EntryDetail; now: Date }) {
  const days = occurrenceWindow(occurrenceOf(entry), true);
  if (!days) return null;
  const today = now.toISOString().slice(0, 10);
  const last = days.last ?? (today > days.first ? today : days.first);
  const firstYear = Number(days.first.slice(0, 4));
  const lastYear = Math.max(firstYear, Number(last.slice(0, 4)));
  const trackStart = Date.UTC(firstYear, 0, 1);
  const trackEnd = Date.UTC(lastYear + 1, 0, 1);
  const position = (iso: string, endOfDay = false) => {
    const time = Date.parse(`${iso}T00:00:00Z`) + (endOfDay ? 86_400_000 : 0);
    return Math.min(
      1,
      Math.max(0, (time - trackStart) / (trackEnd - trackStart)),
    );
  };
  const left = position(days.first);
  const right = 1 - position(last, true);
  const span = chapterSpanLabel(entry);
  return (
    <div className={`${styles.span} ${styles.reading}`}>
      <div
        aria-label={span ? `Chapter span: ${span}` : "Chapter span"}
        className={styles.spanTrack}
        role="img"
      >
        <i
          style={{
            left: `${(left * 100).toFixed(2)}%`,
            right: `${(right * 100).toFixed(2)}%`,
          }}
        />
      </div>
      <div aria-hidden="true" className={styles.spanLabels}>
        <span>Jan {firstYear}</span>
        <span>{days.last ? `Dec ${lastYear}` : "Today"}</span>
      </div>
    </div>
  );
}

function ChapterSections({
  chapter,
  entry,
  onEdit,
}: {
  chapter: ChapterPageData;
  entry: EntryDetail;
  onEdit: () => void;
}) {
  const { contents, page, showAll } = chapter;
  const total = contents?.totalCount ?? 0;
  const pageCount = Math.max(1, Math.ceil(total / chapterEntriesPageSize));
  const overlaps = contents?.overlaps ?? [];
  const now = new Date(chapter.now);
  const occurrence = occurrenceOf(entry);
  const entriesHeadingId = useId();
  const relatedHeadingId = useId();
  // A list a couple of rows longer than the preview shows whole rather than hiding so few.
  const preview = !showAll && total > chapterPreviewCount + 2;
  const entries = contents
    ? preview
      ? contents.entries.slice(0, chapterPreviewCount)
      : contents.entries
    : [];

  return (
    <>
      {chapter.review ? (
        <div className={`${styles.review} ${styles.reading}`}>
          <ReviewPanel
            data={chapter.review.data}
            preferences={chapter.review.preferences}
            spanLabel={chapterDateFacts(entry, now).span}
            subject={{ chapterId: entry.id, scope: "chapter" }}
            timezone={chapter.review.timezone}
            today={chapter.review.today}
          />
        </div>
      ) : null}
      <section
        aria-labelledby={entriesHeadingId}
        className={styles.section}
        id="chapter-entries"
      >
        <SectionHeader
          detail={
            contents && !contents.failed && total > 0
              ? String(total)
              : undefined
          }
          headingId={entriesHeadingId}
          title="Entries in this Chapter"
        />
        {!contents ? (
          <div className={styles.empty}>
            <p>Add a rough start date to see the Entries from this time.</p>
            <Button variant="secondary" onClick={onEdit} type="button">
              Add a start date
            </Button>
          </div>
        ) : contents.failed ? (
          <p className={styles.alert} role="alert">
            The Entries in this Chapter could not load. Refresh to try again.
          </p>
        ) : entries.length === 0 ? (
          <p className={styles.empty}>
            No Entries are dated inside this Chapter yet.
          </p>
        ) : (
          <>
            <EntryRowList label="Entries in this Chapter">
              {entries.map((item) => {
                const labels = entryRowLabels({
                  now,
                  occurrence: item.occurrence,
                  title: item.title,
                });
                return (
                  <EntryRow
                    date={labels.date}
                    dateTime={labels.dateTime}
                    excerpt={item.excerpt || undefined}
                    href={wikiEntryHref(item)}
                    isFirstTime={item.isFirstTime}
                    key={item.id}
                    tags={item.tagNames}
                    thumbnail={
                      item.coverPhoto
                        ? { alt: "", src: item.coverPhoto.imageUrl }
                        : null
                    }
                    title={labels.title}
                  />
                );
              })}
            </EntryRowList>
            {preview ? (
              <Link
                className={styles.showAll}
                href={`/items/${entry.id}?page=1#chapter-entries`}
              >
                Show all {total} Entries
              </Link>
            ) : null}
            {showAll && pageCount > 1 ? (
              <nav
                aria-label="Chapter Entry pages"
                className={styles.pagination}
              >
                {page > 1 ? (
                  <Link href={chapterPageHref(entry.id, page - 1)}>
                    Previous
                  </Link>
                ) : (
                  <span />
                )}
                <span>
                  Page {page} of {pageCount}
                </span>
                {page < pageCount ? (
                  <Link href={chapterPageHref(entry.id, page + 1)}>Next</Link>
                ) : (
                  <span />
                )}
              </nav>
            ) : null}
          </>
        )}
      </section>

      {overlaps.length > 0 ? (
        <section aria-labelledby={relatedHeadingId} className={styles.section}>
          <SectionHeader
            headingId={relatedHeadingId}
            title="Related Chapters"
          />
          <ul aria-label="Related Chapters" className={styles.related}>
            {overlaps.map((overlap) => (
              <li key={overlap.id}>
                <Link href={wikiEntryHref(overlap)}>
                  <span className={styles.relation}>
                    {chapterRelation(occurrence, overlap.occurrence) ===
                    "inside"
                      ? "Inside"
                      : "Overlaps"}
                  </span>
                  <span className={styles.relatedTitle}>{overlap.title}</span>
                  <span className={styles.relatedSpan}>
                    {entryRowDate(overlap.occurrence, {
                      isChapter: true,
                      now,
                    })}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </>
  );
}

function occurrenceOf(entry: EntryDetail): Occurrence {
  return storedOccurrence({
    datePrecision: entry.date_precision,
    occurredEnd: entry.occurred_end,
    occurredLabel: entry.occurred_label,
    occurredStart: entry.occurred_start,
    occurredTimezone: entry.occurred_timezone,
  });
}

function chapterPageHref(id: string, page: number) {
  return `/items/${id}?page=${page}#chapter-entries`;
}
