"use client";
import { EmptyState } from "@/components/empty-state";
import { FocusedViewLayout } from "@/components/focused-view-layout";
import { SeparatedList } from "@/components/separated-list";
import { Button } from "@/components/button";
import { Badge } from "@/components/badge";

import dynamic from "next/dynamic";
import { useState } from "react";
import { useRouter } from "next/navigation";
import styles from "@/components/first-times-workspace.module.css";
import { Icon } from "@/components/icon";
import { ProgressiveImage } from "@/components/progressive-image";
import { RecordCardMap } from "@/components/record-card-map";
import {
  RecordCard,
  RecordCardBody,
  RecordCardVisual,
} from "@/components/record-card";
import type { FirstTimeEntry } from "@/lib/data/first-times";
import { occurrenceLabel, occurrenceSpanLabel } from "@/lib/data/occurrence";
import { locationDisplayLabel } from "@/lib/locations/location";
import { countLabel } from "@/lib/count-label";

const NewEntryDialog = dynamic(() =>
  import("@/components/entry-editor-dialog").then(
    (module) => module.NewEntryDialog,
  ),
);

// First Times are the Entries marked as a First Time. Each opens as an Entry.
export function FirstTimesWorkspace({
  defaultTimezone,
  entries,
  loadError,
  ownerId,
  tagOptions,
}: {
  defaultTimezone: string;
  entries: FirstTimeEntry[];
  loadError: string | null;
  ownerId: string;
  tagOptions: string[];
}) {
  const router = useRouter();
  const [adding, setAdding] = useState(false);
  const photoCount = entries.reduce(
    (count, entry) => count + originalAttachments(entry).length,
    0,
  );

  return (
    <FocusedViewLayout
      actions={
        <Button variant="primary" onClick={() => setAdding(true)} type="button">
          <Icon name="plus" />
          <span>Add First Time</span>
        </Button>
      }
      description={
        <>Keep the small beginnings and big firsts worth finding again.</>
      }
      eyebrow={<>A record of beginnings</>}
      summary={
        <SeparatedList>
          <span>{countLabel(entries.length, "First Time")}</span>
          <span>{countLabel(photoCount, "photo")}</span>
        </SeparatedList>
      }
      summaryLabel="First Times summary"
      title={<>First Times</>}
    >
      {loadError ? (
        <div className={styles.message} role="alert">
          <Icon name="star" size={22} />
          <div>
            <strong>First Times unavailable</strong>
            <p>{loadError}</p>
          </div>
        </div>
      ) : null}

      {!loadError && entries.length === 0 ? (
        <EmptyState
          title={<>Start with a first worth remembering</>}
          icon={
            <>
              <Icon name="star" size={24} />
            </>
          }
          description={
            <>
              Only a title is required. Dates, notes, and photos can come later.
            </>
          }
          onClick={() => setAdding(true)}
        />
      ) : null}

      {!loadError && entries.length > 0 ? (
        <section className={styles.firstGrid} aria-label="First Times archive">
          {entries.map((entry, index) => (
            <FirstTimeCard
              entry={entry}
              index={index}
              key={entry.id}
              onSelect={() => router.push(`/items/${entry.id}`)}
            />
          ))}
        </section>
      ) : null}

      {adding ? (
        <NewEntryDialog
          marks={{ isChapter: false, isFirstTime: true }}
          onClose={() => setAdding(false)}
          ownerId={ownerId}
          tagOptions={tagOptions}
          timezone={defaultTimezone}
        />
      ) : null}
    </FocusedViewLayout>
  );
}

function FirstTimeCard({
  entry,
  index,
  onSelect,
}: {
  entry: FirstTimeEntry;
  index: number;
  onSelect: () => void;
}) {
  const photos = originalAttachments(entry);
  const cover = photos[0];

  return (
    <RecordCard
      ariaLabel={`${entry.title}, ${firstTimeDateLabel(entry)}`}
      className={styles.firstCard}
      onClick={onSelect}
    >
      {cover ? (
        <RecordCardVisual className={styles.coverPhoto}>
          {cover.imageUrl ? (
            <ProgressiveImage alt="" src={cover.imageUrl} />
          ) : (
            <span className={styles.coverFallback}>
              <Icon name="photo" size={22} />
              Private photo
            </span>
          )}
          {photos.length > 1 ? (
            <Badge
              className={styles.photoBadge}
              size="micro"
              tone="inverse"
              uppercase
            >
              {photos.length} photos
            </Badge>
          ) : null}
        </RecordCardVisual>
      ) : (
        <RecordCardVisual className={styles.coverPhoto}>
          <RecordCardMap
            eager={index < 4}
            fallback={
              <span className={styles.cardIndexFallback}>
                {String(index + 1).padStart(2, "0")}
              </span>
            }
            latitude={entry.location?.latitude}
            longitude={entry.location?.longitude}
          />
        </RecordCardVisual>
      )}

      <RecordCardBody className={styles.cardBody}>
        <time dateTime={entry.occurredStart ?? undefined}>
          {firstTimeDateLabel(entry)}
        </time>
        <h2>{entry.title}</h2>
        {entry.location ? (
          <p className={styles.locationLine}>
            <Icon name="map" size={14} />
            {locationDisplayLabel(entry.location)}
          </p>
        ) : null}
        {entry.body ? <p>{truncate(entry.body, 180)}</p> : null}
        <footer>
          <div>
            {entry.tagNames.slice(0, 2).map((name) => (
              <Badge
                key={`tag:${name.toLocaleLowerCase()}`}
                size="micro"
                tone="neutral"
              >
                #{name}
              </Badge>
            ))}
          </div>
          <Icon name="chevron" size={15} />
        </footer>
      </RecordCardBody>
    </RecordCard>
  );
}

function originalAttachments(entry: FirstTimeEntry) {
  return entry.attachments.filter(
    (attachment) => attachment.variant === "original",
  );
}

// A First Time that is also a Chapter spans the time it covered.
function firstTimeDateLabel(entry: FirstTimeEntry) {
  const occurrence = {
    datePrecision: entry.datePrecision,
    occurredAt: entry.occurredStart,
    occurredEnd: entry.occurredEnd,
    occurredLabel: entry.occurredLabel,
    occurredTimezone: entry.occurredTimezone ?? "UTC",
  };
  return entry.isChapter
    ? occurrenceSpanLabel(occurrence)
    : occurrenceLabel(occurrence);
}

function truncate(value: string, limit: number) {
  return value.length > limit ? `${value.slice(0, limit).trimEnd()}…` : value;
}
