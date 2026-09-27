import Link from "next/link";
import type { ReactNode } from "react";
import { CaptureComposer } from "@/components/capture-composer";
import { Icon, type IconName } from "@/components/icon";
import { PageFrame } from "@/components/page-frame";
import { PageHeader } from "@/components/page-header";
import { ProgressiveImage } from "@/components/progressive-image";
import type {
  HomeEntry,
  HomeResurfacedMemory,
  HomeSnapshot,
  HomeStage,
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
import { wikiEntryHref, wikiItemIdentityLabel } from "@/lib/data/wiki-item";
import { type HomeIdeaSlug } from "@/lib/home-ideas";
import styles from "./home-idea.module.css";

export function HomeIdea({
  concept,
  workspace,
}: {
  concept: HomeIdeaSlug;
  workspace: HomeWorkspace;
}) {
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
  const capture = (
    <CaptureComposer
      embedded
      ownerId={viewer.id}
      idPrefix="home-idea-capture"
    />
  );
  const inbox = <Inbox workspace={workspace} />;
  const chapters = snapshot ? (
    <Chapters stages={snapshot.currentStages} />
  ) : null;
  const memory = snapshot ? (
    <Memory memory={workspace.resurfacedMemory} />
  ) : null;
  const recent = snapshot ? <Recent entries={snapshot.recentEntries} /> : null;
  const content = (
    <div className={styles.ribbon}>
      {greeting}
      {snapshot ? <Stats snapshot={snapshot} /> : null}
      <div className={styles.ribbonColumns}>
        <div className={styles.stack}>
          {capture}
          {inbox}
          {recent}
        </div>
        <div className={styles.stack}>
          {memory}
          {chapters}
        </div>
      </div>
    </div>
  );

  return (
    <PageFrame variant="wide" className={styles.page} data-home-idea={concept}>
      {workspace.loadError ? (
        <p className={styles.loadError} role="alert">
          {workspace.loadError}
        </p>
      ) : null}
      {content}
    </PageFrame>
  );
}

function Section({
  title,
  detail,
  href,
  action,
  children,
}: {
  title: string;
  detail?: string;
  href: string;
  action: string;
  children: ReactNode;
}) {
  return (
    <section className={styles.section} aria-label={title}>
      <header className={styles.sectionHeading}>
        <div>
          <h2>{title}</h2>
          {detail ? <p>{detail}</p> : null}
        </div>
        <Link href={href}>
          {action}
          <Icon name="chevron" size={14} />
        </Link>
      </header>
      {children}
    </section>
  );
}

function Inbox({ workspace }: { workspace: HomeWorkspace }) {
  return (
    <Section
      title="Ready to organize"
      href="/inbox"
      action={
        workspace.snapshot
          ? `Inbox · ${workspace.snapshot.inboxCount}`
          : "Open Inbox"
      }
    >
      {workspace.inboxPreview.length ? (
        <div className={styles.inboxList}>
          {workspace.inboxPreview.map((entry) => {
            const title =
              entry.title?.trim() ||
              entry.body.trim().split(/\r?\n/)[0] ||
              "Untitled capture";
            return (
              <Link
                className={styles.inboxItem}
                href={`/inbox?entry=${entry.id}`}
                aria-label={`Organize ${truncate(title, 90)}`}
                key={entry.id}
              >
                <time dateTime={entry.createdAt}>
                  {dateLabel(entry.createdAt, workspace.timezone, false)}
                </time>
                <div>
                  <strong>{truncate(title, 90)}</strong>
                  {entry.title?.trim() && entry.body.trim() ? (
                    <p>{truncate(entry.body, 120)}</p>
                  ) : null}
                </div>
                <Icon name="chevron" size={14} />
              </Link>
            );
          })}
        </div>
      ) : (
        <Empty
          icon="inbox"
          title="A little room to think"
          text="Your Inbox is clear. New captures will wait here until you are ready to organize them."
        />
      )}
    </Section>
  );
}

function Stats({ snapshot }: { snapshot: HomeSnapshot }) {
  const items = [
    {
      value: snapshot.currentStageCount,
      label: "Life in progress",
      href: "/timeline",
    },
    { value: snapshot.entryCount, label: "Entries kept", href: "/library" },
    {
      value: snapshot.firstTimeCount,
      label: "First Times",
      href: "/first-times",
    },
    {
      value: snapshot.collectionCount,
      label: "Collections",
      href: "/collections",
    },
    { value: snapshot.inboxCount, label: "To organize", href: "/inbox" },
  ];
  return (
    <nav className={styles.metrics} aria-label="Your archive at a glance">
      {items.map((item) => (
        <Link href={item.href} key={item.label} className={styles.stat}>
          <strong>{item.value}</strong>
          <span>{item.label}</span>
        </Link>
      ))}
    </nav>
  );
}

function Chapters({ stages }: { stages: HomeStage[] }) {
  return (
    <Section title="Current chapters" href="/timeline" action="Timeline">
      {stages.length ? (
        <div className={styles.chapters}>
          {stages.map((stage) => (
            <Link
              className={styles.chapter}
              key={`${stage.trackId}:${stage.entryId}`}
              href={`/timeline?entry=${stage.entryId}`}
            >
              <div>
                <span className={styles.eyebrow}>{stage.trackName}</span>
                <h3>{stage.title}</h3>
              </div>
              <p>{occurrenceSpanLabel(entryOccurrence(stage))}</p>
            </Link>
          ))}
        </div>
      ) : (
        <Empty
          icon="timeline"
          title="Life is still unfolding"
          text="Current periods and focused records from your Timeline will appear here."
        />
      )}
    </Section>
  );
}

function Memory({ memory }: { memory: HomeResurfacedMemory | null }) {
  const detail =
    memory?.resurfacingKind === "on_this_day" && memory.yearsAgo
      ? `On this day, ${memory.yearsAgo} ${memory.yearsAgo === 1 ? "year" : "years"} ago`
      : "A quiet note from your archive";
  return (
    <Section
      title="A memory for today"
      detail={memory ? detail : undefined}
      href="/library"
      action="Library"
    >
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
          <span>
            {wikiItemIdentityLabel(entry.itemKind, entry.itemSubtype)}
          </span>
          <span>{occurrenceLabel(entryOccurrence(entry))}</span>
        </header>
        <h3>{entry.title || truncate(entry.body, 72) || "Untitled Entry"}</h3>
        {entry.body.trim() ? (
          <p>{truncate(entry.body.trim(), memory ? 260 : 170)}</p>
        ) : null}
        {entry.collectionNames.length || entry.tagNames.length ? (
          <footer className={styles.tags}>
            {entry.collectionNames.slice(0, 2).map((name) => (
              <span key={`collection:${name}`}>{name}</span>
            ))}
            {entry.tagNames.slice(0, 3).map((name) => (
              <span key={`tag:${name}`}>#{name}</span>
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
      <Icon name={icon} size={20} />
      <div>
        <h3>{title}</h3>
        <p>{text}</p>
      </div>
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

function entryOccurrence(entry: HomeEntry | HomeStage): Occurrence {
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

function truncate(value: string, length: number) {
  return value.length <= length
    ? value
    : `${value.slice(0, length).trimEnd()}…`;
}
