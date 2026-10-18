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
  entryDisplayTitle,
  occurrenceLabel,
  occurrenceSpanLabel,
  storedOccurrence,
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
      description="A calm view of what is going on and what you have kept."
    />
  );
  const capture = <CaptureComposer embedded idPrefix="capture" />;
  const nowItems = snapshot ? (
    <Now items={snapshot.nowItems} timezone={timezone} />
  ) : null;
  const memory = snapshot ? (
    <Memory memory={workspace.resurfacedMemory} timezone={timezone} />
  ) : null;
  const recent = snapshot ? (
    <Recent entries={snapshot.recentEntries} timezone={timezone} />
  ) : null;
  const content = (
    <div className={styles.dashboard}>
      {greeting}
      {snapshot ? <Stats snapshot={snapshot} /> : null}
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

function Stats({ snapshot }: { snapshot: HomeSnapshot }) {
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

function Now({ items, timezone }: { items: HomeNowItem[]; timezone: string }) {
  return (
    <Section title="Now" href="/timeline" action="Timeline">
      {items.length ? (
        <div className={styles.nowItems}>
          {items.map((item) => {
            const occurrence = storedOccurrence(item, timezone);
            return (
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
                  <h3>{entryDisplayTitle(item.title, occurrence)}</h3>
                </div>
                <p>{occurrenceSpanLabel(occurrence)}</p>
              </Link>
            );
          })}
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

function Memory({
  memory,
  timezone,
}: {
  memory: HomeResurfacedMemory | null;
  timezone: string;
}) {
  return (
    <Section title="A memory for today" href="/library" action="Library">
      {memory ? (
        <EntryCard entry={memory} memory timezone={timezone} />
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

function Recent({
  entries,
  timezone,
}: {
  entries: HomeEntry[];
  timezone: string;
}) {
  return (
    <Section title="Recent Entries" href="/library" action="View all">
      {entries.length ? (
        <div className={styles.recent}>
          {entries.map((entry) => (
            <EntryCard entry={entry} key={entry.id} timezone={timezone} />
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
  timezone,
}: {
  entry: HomeEntry;
  memory?: boolean;
  timezone: string;
}) {
  const cover = entry.attachments.find((attachment) => attachment.imageUrl);
  const occurrence = storedOccurrence(entry, timezone);
  const title = entryDisplayTitle(entry.title, occurrence);
  // An untitled Entry is already named by its date, so the date is not repeated.
  const date = entry.title.trim() ? occurrenceLabel(occurrence) : null;
  const identity = wikiItemIdentityLabel(entry.itemKind, entry.itemSubtype);
  const summary = entry.body.trim();
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
              <span>{identity}</span>
              {date ? <span>{date}</span> : null}
            </>
          ) : (
            <>
              {date ? <span className={styles.entryDate}>{date}</span> : null}
              <Badge size="small" tone="outline">
                {identity}
              </Badge>
            </>
          )}
        </header>
        <h3>{title}</h3>
        {summary ? <p>{truncate(summary, memory ? 260 : 170)}</p> : null}
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

function truncate(value: string, length: number) {
  return value.length <= length
    ? value
    : `${value.slice(0, length).trimEnd()}…`;
}
