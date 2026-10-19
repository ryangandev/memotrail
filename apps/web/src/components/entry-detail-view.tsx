"use client";
import { notify } from "@/components/app-toast";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/button";
import { useConfirmationDialog } from "@/components/confirmation-dialog";
import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { EntryEditorDialog } from "./entry-editor-dialog";
import { EntryPhotos } from "./entry-photos";
import { EntryRichTextContent } from "./entry-rich-text-content";
import { ReviewPanel } from "./review-panel";
import { EntryList } from "./entry-list";
import { Icon } from "./icon";
import { SectionHeader } from "./section-header";
import { SeparatedList } from "./separated-list";
import { loadEditableEntry, trashWikiItem } from "@/app/items/actions";
import {
  chapterDateFacts,
  entryDateAddsToTitle,
  entryDateLabel,
  entryTitle,
  type EntryDetail,
} from "@/lib/data/entry-detail";
import {
  chapterEntriesPageSize,
  type ChapterContents,
} from "@/lib/data/chapter-contents-types";
import {
  entryDisplayTitle,
  occurrenceLabel,
  occurrenceSpanLabel,
} from "@/lib/data/occurrence";
import {
  wikiEntryHref,
  wikiItemIdentityLabel,
  wikiItemSubtypeLabel,
} from "@/lib/data/wiki-item";
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
  /** The Chapter's review, or null when reviews could not be read. */
  review: {
    data: ReviewPageData;
    preferences: ReviewSettings;
    timezone: string;
    today: string;
  } | null;
};

const sourceLinkLabels: Record<string, string> = {
  exploration_source: "Open source item",
  exploration_conclusion: "Open saved conclusion",
};

export function EntryDetailView({
  chapter = null,
  entry,
  ownerId,
  photos,
}: {
  chapter?: ChapterPageData | null;
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
  async function edit() {
    setBusy(true);
    setError(null);
    try {
      const data = await loadEditableEntry(entry.id);
      if (!data) throw Error();
      setEditing(data);
    } catch {
      setError("This item cannot be edited right now. Refresh and try again.");
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
      eyebrow: <>Recoverable action</>,
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
        notify.info("Entry moved to Trash.");
      }
    } catch {
      setError(
        "Could not confirm the move to Trash. Refresh before trying again.",
      );
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <Link className={styles.backLink} href="/library">
        ← Library
      </Link>
      <PageHeader
        eyebrow={
          <>{wikiItemIdentityLabel(entry.item_subtype, entry.is_first_time)}</>
        }
        title={<>{entryTitle(entry)}</>}
      />
      <div className={styles.itemActions}>
        {active && entry.item_kind === "entry" && (
          <Button
            variant="secondary"
            type="submit"
            disabled={busy}
            onClick={() => void edit()}
          >
            Edit {wikiItemSubtypeLabel(entry.item_subtype)}
          </Button>
        )}
        {editing && (
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
        )}
        {active ? (
          <Button
            variant="danger"
            className={styles.trashAction}
            disabled={busy}
            onClick={() => void moveToTrash()}
            type="button"
          >
            <Icon name="trash" size={16} />
            Move to Trash
          </Button>
        ) : null}
      </div>
      {error && <p role="alert">{error}</p>}
      {entry.links.map((link) =>
        sourceLinkLabels[link.relationship] ? (
          <p key={`${link.relationship}:${link.target_entry_id}`}>
            <Link href={`/items/${link.target_entry_id}`}>
              {sourceLinkLabels[link.relationship]}
            </Link>
          </p>
        ) : null,
      )}
      {!active && (
        <p role="status">
          This item is in Trash. Restore it there to change it.
        </p>
      )}
      <CurrentItem
        now={chapter ? new Date(chapter.now) : null}
        photos={active ? photos : { hasMore: false, photos: [] }}
        value={entry}
      />
      {chapter ? (
        <ChapterSections
          chapter={chapter}
          entry={entry}
          onEdit={() => void edit()}
        />
      ) : null}
    </>
  );
}

function CurrentItem({
  now,
  photos,
  value,
}: {
  // Set for a Chapter, whose Date fact also says how long it lasted.
  now: Date | null;
  photos: EntryPhotoList | null;
  value: EntryDetail;
}) {
  const groups = [
    { key: "tags", label: "tags", names: value.tags.map((tag) => tag.name) },
    {
      key: "locations",
      label: "locations",
      names: value.locations.map((location) =>
        locationDisplayLabel({
          formattedAddress: location.formatted_address,
          latitude: location.latitude,
          longitude: location.longitude,
        }),
      ),
    },
  ]
    .filter((group) => group.names.length > 0)
    .map((group) => ({ ...group, value: group.names.join(", ") }));

  return (
    <article className={styles.currentItem} aria-label="Current item">
      <EntryRichTextContent
        body={value.body || "No writing has been added yet."}
        className={styles.currentBody}
        metadata={value.body ? value.metadata : undefined}
      />
      {photos === null ? (
        <p className={styles.photosError} role="alert">
          Photos could not load. Refresh the page to try again.
        </p>
      ) : photos.photos.length > 0 ? (
        <EntryPhotos hasMore={photos.hasMore} photos={photos.photos} />
      ) : null}
      <dl className={styles.currentFacts}>
        {now && value.item_subtype === "chapter" ? (
          <ChapterDate now={now} value={value} />
        ) : entryDateAddsToTitle(value) ? (
          <div>
            <dt>Date</dt>
            <dd className={styles.dateValue}>{entryDateLabel(value)}</dd>
          </div>
        ) : null}
        {groups.map((group) => (
          <div key={group.key}>
            <dt>{group.label}</dt>
            <dd>{group.value}</dd>
          </div>
        ))}
      </dl>
    </article>
  );
}

// A Chapter's Date fact: the span it covers and how long that is. An undated Chapter shows its
// description alone.
function ChapterDate({ now, value }: { now: Date; value: EntryDetail }) {
  const { duration, span } = chapterDateFacts(value, now);
  return (
    <div>
      <dt>Date</dt>
      <dd className={styles.dateValue}>
        <SeparatedList>
          <span>{span}</span>
          {duration ? <span>{duration}</span> : null}
        </SeparatedList>
      </dd>
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
  const { contents, page } = chapter;
  const total = contents?.totalCount ?? 0;
  const pageCount = Math.max(1, Math.ceil(total / chapterEntriesPageSize));
  const overlaps = contents?.overlaps ?? [];

  return (
    <>
      {chapter.review ? (
        <ReviewPanel
          data={chapter.review.data}
          preferences={chapter.review.preferences}
          spanLabel={chapterDateFacts(entry, new Date(chapter.now)).span}
          subject={{ chapterId: entry.id, scope: "chapter" }}
          timezone={chapter.review.timezone}
          today={chapter.review.today}
        />
      ) : null}
      <section aria-labelledby="chapter-entries-heading">
        <SectionHeader
          detail={
            contents && !contents.failed
              ? `${total} ${total === 1 ? "Entry" : "Entries"}`
              : undefined
          }
          headingId="chapter-entries-heading"
          title="In this Chapter"
        />
        {!contents ? (
          <div className={styles.chapterEmpty}>
            <p>Add a rough start date to see the Entries from this time.</p>
            <Button variant="secondary" onClick={onEdit} type="button">
              Add a start date
            </Button>
          </div>
        ) : contents.failed ? (
          <p role="alert">
            The Entries in this Chapter could not load. Refresh to try again.
          </p>
        ) : contents.entries.length === 0 ? (
          <p className={styles.chapterEmpty}>
            No Entries are dated inside this Chapter yet.
          </p>
        ) : (
          <>
            <EntryList
              items={contents.entries.map((item) => {
                // An untitled Entry is already named by its date.
                const title = entryDisplayTitle(item.title, item.occurrence);
                return {
                  cover: item.coverPhoto
                    ? {
                        alt: item.coverPhoto.alt,
                        src: item.coverPhoto.imageUrl,
                      }
                    : null,
                  date: item.title.trim()
                    ? occurrenceLabel(item.occurrence)
                    : null,
                  excerpt: item.excerpt,
                  href: wikiEntryHref(item),
                  id: item.id,
                  isChapter: false,
                  isFirstTime: item.isFirstTime,
                  title,
                };
              })}
              label="Entries in this Chapter"
            />
            {pageCount > 1 ? (
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
        <section aria-labelledby="chapter-overlaps-heading">
          <SectionHeader
            headingId="chapter-overlaps-heading"
            title="Chapters during this time"
          />
          <ul
            aria-label="Chapters during this time"
            className={styles.overlaps}
          >
            {overlaps.map((overlap) => (
              <li key={overlap.id}>
                <Link href={wikiEntryHref(overlap)}>{overlap.title}</Link>
                <small>{occurrenceSpanLabel(overlap.occurrence)}</small>
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </>
  );
}

function chapterPageHref(id: string, page: number) {
  return page > 1 ? `/items/${id}?page=${page}` : `/items/${id}`;
}
