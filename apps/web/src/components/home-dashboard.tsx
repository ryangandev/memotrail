import Link from "next/link";
import type { ReactNode } from "react";
import { EmptyState } from "@/components/empty-state";
import { CaptureComposer } from "@/components/capture-composer";
import { Icon, type IconName } from "@/components/icon";
import { PageFrame } from "@/components/page-frame";
import { PageHeader } from "@/components/page-header";
import { ProgressiveImage } from "@/components/progressive-image";
import { SectionHeader } from "@/components/section-header";
import { Badge } from "@/components/badge";
import type {
  HomeEntry,
  HomeResurfacedMemory,
  HomeSnapshot,
  HomeNowItem,
  HomeWorkspace,
} from "@/lib/data/home";
import { greetingInTimezone } from "@/lib/data/home-input";
import {
  occurrenceLabel,
  occurrencePrecisions,
  occurrenceSpanLabel,
  validTimezone,
  type Occurrence,
} from "@/lib/data/occurrence";
import { timelineLaneLabels } from "@/lib/data/milestone";
import { wikiEntryHref, wikiItemIdentityLabel } from "@/lib/data/wiki-item";
import styles from "./home-dashboard.module.css";

export function HomeDashboard({ workspace }: { workspace: HomeWorkspace }) {
  const { snapshot, viewer, timezone } = workspace;
  const now = new Date();
  const name =
    (snapshot?.profileDisplayName || viewer.name).trim().split(/\s+/)[0] ||
    "there";
  const greeting = (
    <PageHeader
      eyebrow={new Intl.DateTimeFormat("en-US", {
        weekday: "long",
        month: "long",
        day: "numeric",
        timeZone: timezone,
      }).format(now)}
      title={
        <>
          {greetingInTimezone(now, timezone)}, {name}.
        </>
      }
      description="A calm view of what is active, recent, and waiting for you."
    />
  );
  const capture = <CaptureComposer embedded idPrefix="capture" />;
  const needsOrganizing = (
    <NeedsOrganizing
      needsOrganizing={workspace.needsOrganizing}
      timezone={workspace.timezone}
    />
  );
  const nowItems = snapshot ? <Now items={snapshot.nowItems} /> : null;
  const memory = snapshot ? (
    <Memory memory={workspace.resurfacedMemory} />
  ) : null;
  const recent = snapshot ? <Recent entries={snapshot.recentEntries} /> : null;
  const content = (
    <div className={styles.dashboard}>
      {greeting}
      {snapshot ? (
        <Stats
          needsOrganizingCount={workspace.needsOrganizing?.count ?? null}
          snapshot={snapshot}
        />
      ) : null}
      {workspace.loadError || !snapshot ? (
        <>
          <div className={styles.loadError} role="alert">
            <strong>Home is taking a moment</strong>
            <p>{workspace.loadError || "Refresh to try again."}</p>
          </div>
          {capture}
        </>
      ) : (
        <div className={styles.columns}>
          <div className={styles.capturePanel}>{capture}</div>
          <div className={styles.organizePanel}>{needsOrganizing}</div>
          <div className={styles.memoryColumn}>{memory}</div>
          <div className={styles.nowColumn}>{nowItems}</div>
          <div className={styles.recentRow}>{recent}</div>
        </div>
      )}
    </div>
  );

  return (
    <PageFrame variant="wide" className={styles.page}>
      {content}
    </PageFrame>
  );
}

function Section({
  title,
  href,
  action,
  children,
}: {
  title: string;
  href: string;
  action: string;
  children: ReactNode;
}) {
  return (
    <section className={styles.section} aria-label={title}>
      <SectionHeader
        action={
          <Link className={styles.sectionLink} href={href}>
            {action}
            <Icon name="chevron" size={14} />
          </Link>
        }
        className={styles.sectionHeading}
        title={title}
      />
      {children}
    </section>
  );
}

function NeedsOrganizing({
  needsOrganizing,
  timezone,
}: {
  needsOrganizing: HomeWorkspace["needsOrganizing"];
  timezone: string;
}) {
  return (
    <Section
      title="Needs organizing"
      href={needsOrganizingHref}
      action={
        needsOrganizing?.count
          ? `Library · ${needsOrganizing.count}`
          : "Library"
      }
    >
      {needsOrganizing?.items.length ? (
        <div className={styles.organizeList}>
          {needsOrganizing.items.map((item) => (
            <Link
              className={styles.organizeItem}
              href={wikiEntryHref(item)}
              aria-label={`Organize ${truncate(item.title, 90)}`}
              key={item.id}
            >
              <time dateTime={item.updatedAt}>
                {dateLabel(item.updatedAt, timezone, false)}
              </time>
              <div>
                <strong>{item.title}</strong>
              </div>
              <Icon name="chevron" size={14} />
            </Link>
          ))}
        </div>
      ) : needsOrganizing ? (
        <Empty
          icon="check"
          title="Everything has a place"
          text="Captures without a title or tag show up here, so you can sort them when you are ready."
        />
      ) : (
        <Empty
          icon="clock"
          title="Not available right now"
          text="MemoTrail could not check what needs organizing. Refresh to try again."
        />
      )}
    </Section>
  );
}

const needsOrganizingHref = "/library?show=needs-organizing";

function Stats({
  needsOrganizingCount,
  snapshot,
}: {
  needsOrganizingCount: number | null;
  snapshot: HomeSnapshot;
}) {
  const items = [
    {
      value: snapshot.nowCount,
      label: "Going on now",
      href: "/timeline",
      icon: "timeline",
    },
    {
      value: snapshot.entryCount,
      label: "Entries kept",
      href: "/library",
      icon: "archive",
    },
    {
      value: snapshot.firstTimeCount,
      label: "First Times",
      href: "/first-times",
      icon: "star",
    },
    {
      value: snapshot.tagCount,
      label: "Tags",
      href: "/tags",
      icon: "tag",
    },
    ...(needsOrganizingCount === null
      ? []
      : [
          {
            value: needsOrganizingCount,
            label: "To organize",
            href: needsOrganizingHref,
            icon: "inbox",
          } as const,
        ]),
  ] as const;
  return (
    <nav className={styles.metrics} aria-label="Your archive at a glance">
      {items.map((item) => (
        <Link href={item.href} key={item.label} className={styles.stat}>
          <Icon name={item.icon} size={16} />
          <strong>{item.value}</strong>
          <span>{item.label}</span>
        </Link>
      ))}
    </nav>
  );
}

function Now({ items }: { items: HomeNowItem[] }) {
  return (
    <Section title="Now" href="/timeline" action="Timeline">
      {items.length ? (
        <div className={styles.nowItems}>
          {items.map((item) => (
            <Link
              className={styles.nowItem}
              key={item.entryId}
              href={wikiEntryHref({
                id: item.entryId,
                itemKind: item.itemKind,
                itemSubtype: item.itemSubtype,
              })}
            >
              <div>
                <span className={styles.eyebrow}>
                  {timelineLaneLabels[item.lane]}
                </span>
                <h3>{item.title}</h3>
              </div>
              <p>{occurrenceSpanLabel(entryOccurrence(item))}</p>
            </Link>
          ))}
        </div>
      ) : (
        <Empty
          icon="timeline"
          title="Life is still unfolding"
          text="The home you live in, the vehicle you drive, and the Periods still going on will appear here."
        />
      )}
    </Section>
  );
}

function Memory({ memory }: { memory: HomeResurfacedMemory | null }) {
  return (
    <Section title="A memory for today" href="/library" action="Library">
      {memory ? (
        <EntryCard entry={memory} memory />
      ) : (
        <Empty
          icon="sparkle"
          title="Room for a memory"
          text="As your archive grows, an older dated Entry will find its way back here."
        />
      )}
    </Section>
  );
}

function Recent({ entries }: { entries: HomeEntry[] }) {
  return (
    <Section title="Recent Entries" href="/library" action="View all">
      {entries.length ? (
        <div className={styles.recent}>
          {entries.map((entry) => (
            <EntryCard entry={entry} key={entry.id} />
          ))}
        </div>
      ) : (
        <Empty
          icon="archive"
          title="Your trail starts here"
          text="Entries you save to Library will appear here, ready to return to."
        />
      )}
    </Section>
  );
}

function EntryCard({
  entry,
  memory = false,
}: {
  entry: HomeEntry;
  memory?: boolean;
}) {
  const cover = entry.attachments.find((attachment) => attachment.imageUrl);
  const title = entry.title || truncate(entry.body, 72) || "Untitled Entry";
  const excerpt = excerptAfterTitle(entry.title, entry.body);
  return (
    <Link
      href={wikiEntryHref(entry)}
      className={[
        memory ? styles.memoryCard : styles.entryCard,
        cover ? styles.withPhoto : "",
      ].join(" ")}
    >
      {cover ? (
        <ProgressiveImage
          className={memory ? styles.memoryPhoto : styles.entryPhoto}
          src={cover.imageUrl!}
          alt={cover.originalFilename || "Entry photo"}
          loading="lazy"
        />
      ) : null}
      <article>
        <header className={styles.entryMeta}>
          {memory ? (
            <>
              <span>
                {wikiItemIdentityLabel(entry.itemKind, entry.itemSubtype)}
              </span>
              <span>{occurrenceLabel(entryOccurrence(entry))}</span>
            </>
          ) : (
            <>
              <span className={styles.entryDate}>
                {occurrenceLabel(entryOccurrence(entry))}
              </span>
              <Badge size="small" tone="outline">
                {wikiItemIdentityLabel(entry.itemKind, entry.itemSubtype)}
              </Badge>
            </>
          )}
        </header>
        <h3>{title}</h3>
        {excerpt ? <p>{truncate(excerpt, memory ? 260 : 170)}</p> : null}
        {entry.tagNames.length ? (
          <footer className={styles.tags}>
            {entry.tagNames.slice(0, 3).map((name) => (
              <Badge key={`tag:${name}`} size="medium" title={`#${name}`}>
                #{name}
              </Badge>
            ))}
          </footer>
        ) : null}
      </article>
    </Link>
  );
}

function Empty({
  icon,
  title,
  text,
}: {
  icon: IconName;
  title: string;
  text: string;
}) {
  return (
    <div className={styles.empty}>
      <EmptyState
        headingLevel={3}
        icon={<Icon name={icon} size={20} />}
        title={title}
        description={text}
      />
    </div>
  );
}

function dateLabel(value: string, timezone: string | null, year = true) {
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    ...(year ? { year: "numeric" as const } : {}),
    timeZone: timezone || "UTC",
  }).format(new Date(value));
}

function entryOccurrence(entry: HomeEntry | HomeNowItem): Occurrence {
  return {
    occurredAt: entry.occurredStart,
    occurredEnd: entry.occurredEnd,
    occurredLabel: entry.occurredLabel,
    occurredTimezone: validTimezone(entry.occurredTimezone)
      ? entry.occurredTimezone
      : "UTC",
    datePrecision:
      occurrencePrecisions.find(
        (precision) => precision === entry.datePrecision,
      ) || "unknown",
  };
}

// An Entry without a title is shown by its first line, so the excerpt starts
// after that line instead of repeating it.
function excerptAfterTitle(title: string, body: string) {
  const text = body.trim();
  const [firstLine = "", ...rest] = text.split(/\r?\n/);
  return firstLine.trim() === title.trim() ? rest.join("\n").trim() : text;
}

function truncate(value: string, length: number) {
  return value.length <= length
    ? value
    : `${value.slice(0, length).trimEnd()}…`;
}
