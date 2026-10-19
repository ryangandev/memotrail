import Link from "next/link";
import { useId, type ReactNode } from "react";
import { ButtonLink } from "@/components/button";
import { CaptureComposer } from "@/components/capture-composer";
import { EmptyState } from "@/components/empty-state";
import {
  ChapterMark,
  EntryRow,
  EntryRowList,
  FirstTimeMark,
} from "@/components/entry-row";
import { PageFrame } from "@/components/page-frame";
import { PageHeader } from "@/components/page-header";
import { ProgressiveImage } from "@/components/progressive-image";
import { ReviewNoticeCard } from "@/components/review-notice-card";
import { SectionHeader } from "@/components/section-header";
import { SeparatedList } from "@/components/separated-list";
import { countLabel } from "@/lib/count-label";
import { entryRowLabels } from "@/lib/data/entry-row";
import type {
  HomeEntry,
  HomeNowItem,
  HomeResurfacedMemory,
  HomeSnapshot,
  HomeWorkspace,
} from "@/lib/data/home";
import { greetingInTimezone } from "@/lib/data/home-input";
import {
  entryDisplayTitle,
  occurrenceDurationLabel,
  occurrenceSpanLabel,
  occurrenceTitle,
  storedOccurrence,
} from "@/lib/data/occurrence";
import type { ReviewNotice } from "@/lib/data/review-input";
import { wikiEntryHref } from "@/lib/data/wiki-item";
import styles from "./home-dashboard.module.css";

/**
 * The Dashboard: a greeting with one line of counts, the composer, the Chapters going on now
 * beside a memory from the past, and the most recent Entries. Specified in docs/product.md.
 */
export function HomeDashboard({
  firstTimeIds = [],
  reviewNotice = null,
  workspace,
}: {
  /** Which of the recent Entries are First Times, which the snapshot does not say. */
  firstTimeIds?: readonly string[];
  /** The one review notice to show, when reviews are on and one is due. */
  reviewNotice?: ReviewNotice | null;
  workspace: HomeWorkspace;
}) {
  const { snapshot, viewer, timezone } = workspace;
  const now = new Date();
  const name =
    (snapshot?.profileDisplayName || viewer.name).trim().split(/\s+/)[0] ||
    "there";
  const today = new Intl.DateTimeFormat("en-US", {
    weekday: "long",
    month: "long",
    day: "numeric",
    timeZone: timezone,
  }).format(now);
  const capture = <CaptureComposer embedded idPrefix="capture" />;

  return (
    <PageFrame width="list">
      <div className={styles.dashboard}>
        <PageHeader
          meta={<Glance snapshot={snapshot} today={today} />}
          title={`${greetingInTimezone(now, timezone)}, ${name}`}
        />
        {workspace.loadError || !snapshot ? (
          <>
            <div className={styles.loadError} role="alert">
              <strong>Home is taking a moment</strong>
              <p>{workspace.loadError || "Refresh to try again."}</p>
            </div>
            <div className={styles.capture}>{capture}</div>
          </>
        ) : (
          <>
            <div className={styles.capture}>{capture}</div>
            {reviewNotice ? (
              <div className={styles.notice}>
                <ReviewNoticeCard notice={reviewNotice} />
              </div>
            ) : null}
            {snapshot.entryCount === 0 ? (
              <div className={styles.firstEntry}>
                <EmptyState
                  actions={
                    <ButtonLink href="/settings/import" variant="secondary">
                      Import Entries
                    </ButtonLink>
                  }
                  description="Write your first Entry above, or bring in notes you already have."
                  title="Your Library starts here"
                />
              </div>
            ) : (
              <>
                <div className={styles.columns}>
                  <Now
                    items={snapshot.nowItems}
                    snapshotDate={snapshot.snapshotDate}
                  />
                  <Memory
                    memory={workspace.resurfacedMemory}
                    timezone={timezone}
                  />
                </div>
                <Recent
                  entries={snapshot.recentEntries}
                  firstTimeIds={firstTimeIds}
                  now={now}
                  timezone={timezone}
                />
              </>
            )}
          </>
        )}
      </div>
    </PageFrame>
  );
}

/** Today's date and the counts that lead to their destinations, as one muted line. */
function Glance({
  snapshot,
  today,
}: {
  snapshot: HomeSnapshot | null;
  today: string;
}) {
  // A new Library has nothing to count yet, so the line is only the date.
  const counts = snapshot?.entryCount
    ? [
        { count: snapshot.entryCount, href: "/library", noun: "Entry" },
        {
          count: snapshot.nowCount,
          href: "/timeline",
          noun: "Chapter",
          suffix: " now",
        },
        {
          count: snapshot.firstTimeCount,
          href: "/first-times",
          noun: "First Time",
        },
        { count: snapshot.tagCount, href: "/tags", noun: "Tag" },
      ].filter((item) => item.count > 0)
    : [];
  return (
    <div className={styles.glance}>
      <span className={styles.today}>
        {today}
        {counts.length ? (
          <span aria-hidden="true" className={styles.dot}>
            ·
          </span>
        ) : null}
      </span>
      {counts.length ? (
        <nav aria-label="Your Library at a glance">
          <SeparatedList>
            {counts.map((item) => (
              <Link href={item.href} key={item.noun}>
                {countLabel(
                  item.count,
                  item.noun,
                  item.noun === "Entry" ? "Entries" : undefined,
                )}
                {item.suffix ?? ""}
              </Link>
            ))}
          </SeparatedList>
        </nav>
      ) : null}
    </div>
  );
}

function Section({
  action,
  children,
  href,
  id,
  title,
}: {
  action?: string;
  children: ReactNode;
  href?: string;
  id: string;
  title: string;
}) {
  return (
    <section aria-labelledby={id} className={styles.section}>
      <SectionHeader
        action={
          action && href ? (
            <Link className={styles.sectionLink} href={href}>
              {action}
            </Link>
          ) : null
        }
        headingId={id}
        title={title}
      />
      {children}
    </section>
  );
}

function Now({
  items,
  snapshotDate,
}: {
  items: HomeNowItem[];
  snapshotDate: string;
}) {
  // Durations are measured to the day this snapshot describes.
  const asOf = new Date(`${snapshotDate}T12:00:00Z`);
  const id = useId();
  return (
    <Section action="Timeline" href="/timeline" id={id} title="Now">
      {items.length ? (
        <ul className={styles.nowList}>
          {items.map((item) => (
            <li key={item.id}>
              <Link className={styles.nowItem} href={wikiEntryHref(item)}>
                <span className={styles.nowName}>
                  <ChapterMark />
                  {item.isFirstTime ? <FirstTimeMark /> : null}
                  <span className={styles.nowTitle}>{item.title}</span>
                </span>
                <span className={styles.nowDuration}>
                  <span className={styles.nowSpan}>
                    {occurrenceSpanLabel(item.occurrence)}
                    <span aria-hidden="true" className={styles.dot}>
                      ·
                    </span>
                  </span>
                  {occurrenceDurationLabel(item.occurrence, asOf)}
                </span>
              </Link>
            </li>
          ))}
        </ul>
      ) : (
        <EmptyState
          description="A Chapter with no end date shows here."
          headingLevel={3}
          title="No Chapter is going on right now"
        />
      )}
    </Section>
  );
}

function Memory({
  memory,
  timezone,
}: {
  memory: HomeResurfacedMemory | null;
  timezone: string;
}) {
  const id = useId();
  return (
    <Section id={id} title="From your past">
      {memory ? (
        <MemoryCard memory={memory} timezone={timezone} />
      ) : (
        <EmptyState
          description="As your Library grows, an older dated Entry will find its way back here."
          headingLevel={3}
          title="Nothing from your past yet"
        />
      )}
    </Section>
  );
}

function MemoryCard({
  memory,
  timezone,
}: {
  memory: HomeResurfacedMemory;
  timezone: string;
}) {
  const cover = memory.attachments.find((attachment) => attachment.imageUrl);
  const occurrence = storedOccurrence(memory, timezone);
  const title = entryDisplayTitle(memory.title, occurrence);
  // An untitled Entry is already named by its date, so the date is not repeated.
  const date = memory.title.trim() ? occurrenceTitle(occurrence) : null;
  const ago =
    memory.resurfacingKind === "on_this_day" && memory.yearsAgo
      ? `${memory.yearsAgo === 1 ? "One year" : `${memory.yearsAgo} years`} ago today`
      : null;
  const summary = memory.body.replace(/\s+/g, " ").trim();
  return (
    <Link className={styles.memory} href={wikiEntryHref(memory)}>
      {cover ? (
        <ProgressiveImage
          alt={cover.originalFilename || "Entry photo"}
          className={styles.memoryPhoto}
          loading="lazy"
          src={cover.imageUrl!}
        />
      ) : null}
      <article className={styles.memoryBody}>
        {ago || date ? (
          <p className={styles.memoryWhen}>
            {ago}
            {date ? (
              <span className={ago ? styles.memoryDate : undefined}>
                {ago ? (
                  <span aria-hidden="true" className={styles.dot}>
                    ·
                  </span>
                ) : null}
                {date}
              </span>
            ) : null}
          </p>
        ) : null}
        <h3 className={styles.memoryTitle}>{title}</h3>
        {summary ? <p className={styles.memoryExcerpt}>{summary}</p> : null}
      </article>
    </Link>
  );
}

function Recent({
  entries,
  firstTimeIds,
  now,
  timezone,
}: {
  entries: HomeEntry[];
  firstTimeIds: readonly string[];
  now: Date;
  timezone: string;
}) {
  const firstTimes = new Set(firstTimeIds);
  const id = useId();
  return (
    <div className={styles.recent}>
      <Section action="All in Library" href="/library" id={id} title="Recent">
        {entries.length ? (
          <EntryRowList labelledBy={id}>
            {entries.map((entry) => {
              const isChapter = entry.itemSubtype === "chapter";
              const labels = entryRowLabels({
                isChapter,
                now,
                occurrence: storedOccurrence(entry, timezone),
                title: entry.title,
              });
              const photo = entry.attachments.find(
                (attachment) => attachment.imageUrl,
              );
              const excerpt = entry.body.replace(/\s+/g, " ").trim();
              return (
                <EntryRow
                  date={labels.date}
                  dateTime={labels.dateTime}
                  excerpt={excerpt ? truncate(excerpt, 220) : null}
                  href={wikiEntryHref(entry)}
                  isChapter={isChapter}
                  isFirstTime={firstTimes.has(entry.id)}
                  key={entry.id}
                  tags={entry.tagNames}
                  thumbnail={
                    photo
                      ? { alt: "", src: `${photo.imageUrl}&variant=thumbnail` }
                      : null
                  }
                  title={labels.title}
                />
              );
            })}
          </EntryRowList>
        ) : (
          <EmptyState
            description="Entries you save appear here, ready to return to."
            headingLevel={3}
            title="Nothing recent yet"
          />
        )}
      </Section>
    </div>
  );
}

function truncate(value: string, length: number) {
  return value.length <= length
    ? value
    : `${value.slice(0, length).trimEnd()}…`;
}
