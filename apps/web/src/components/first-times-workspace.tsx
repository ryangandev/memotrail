"use client";
import { EmptyState } from "@/components/empty-state";
import { FocusedViewLayout } from "@/components/focused-view-layout";
import { SeparatedList } from "@/components/separated-list";
import { Button } from "@/components/button";

import dynamic from "next/dynamic";
import Link from "next/link";
import { useState } from "react";
import styles from "@/components/first-times-workspace.module.css";
import { ChapterMark } from "@/components/entry-row";
import { Icon } from "@/components/icon";
import { ProgressiveImage } from "@/components/progressive-image";
import { RecordCardMap } from "@/components/record-card-map";
import type { FirstTimeEntry } from "@/lib/data/first-times";
import {
  firstTimeExcerpt,
  firstTimePhotos,
  firstTimeRowDateLabel,
  firstTimeRowDetails,
} from "@/lib/data/first-times-presentation";
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
  const [adding, setAdding] = useState(false);
  const photoCount = entries.reduce(
    (count, entry) => count + firstTimePhotos(entry).length,
    0,
  );

  return (
    <FocusedViewLayout
      action={
        <Button variant="primary" onClick={() => setAdding(true)} type="button">
          <Icon name="plus" />
          <span>Add First Time</span>
        </Button>
      }
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
        <p className={styles.message} role="alert">
          {loadError}
        </p>
      ) : null}

      {!loadError && entries.length === 0 ? (
        <EmptyState
          title={<>Add the first time you did something</>}
          icon={<Icon name="star" size={24} />}
          description={
            <>
              A first trip, a first job, a first meal for friends. You can also
              mark any Entry as a First Time.
            </>
          }
          onClick={() => setAdding(true)}
        />
      ) : null}

      {!loadError && entries.length > 0 ? (
        <ul aria-label="First Times" className={styles.rows}>
          {entries.map((entry, index) => (
            <FirstTimeRow entry={entry} eager={index < 8} key={entry.id} />
          ))}
        </ul>
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

/**
 * One First Time: its date, its title, a line of what happened, where and how it is
 * organized, and its first photo or a map of where it happened.
 */
function FirstTimeRow({
  eager,
  entry,
}: {
  eager: boolean;
  entry: FirstTimeEntry;
}) {
  const date = firstTimeRowDateLabel(entry);
  const excerpt = firstTimeExcerpt(entry.body);
  const details = firstTimeRowDetails(entry);
  const cover = firstTimePhotos(entry)[0];
  const mappable =
    typeof entry.location?.latitude === "number" &&
    typeof entry.location?.longitude === "number";

  return (
    <li className={styles.item}>
      <Link
        aria-label={[entry.title, date, entry.isChapter ? "Chapter" : null]
          .filter(Boolean)
          .join(", ")}
        className={styles.row}
        data-thumbnail={cover || mappable ? "" : undefined}
        data-untitled={entry.untitled ? "" : undefined}
        href={`/items/${entry.id}`}
      >
        <div className={styles.date}>
          {date ? (
            <time dateTime={entry.occurredStart ?? undefined}>{date}</time>
          ) : null}
        </div>
        <div className={styles.body}>
          <h2 className={styles.title}>
            <span className={styles.titleText}>{entry.title}</span>
            {entry.isChapter ? <ChapterMark /> : null}
          </h2>
          {excerpt ? <p className={styles.excerpt}>{excerpt}</p> : null}
          {details.length > 0 ? (
            <p className={styles.details}>{details.join(" · ")}</p>
          ) : null}
        </div>
        {cover ? (
          <span className={styles.thumbnail}>
            <ProgressiveImage
              alt=""
              fallback={<Icon name="photo" size={18} />}
              loading={eager ? "eager" : "lazy"}
              src={cover.imageUrl ?? undefined}
            />
          </span>
        ) : mappable ? (
          <span className={styles.thumbnail}>
            <RecordCardMap
              eager={eager}
              fallback={<Icon name="map" size={18} />}
              latitude={entry.location?.latitude}
              longitude={entry.location?.longitude}
            />
          </span>
        ) : null}
      </Link>
    </li>
  );
}
