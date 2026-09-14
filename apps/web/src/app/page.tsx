import Link from "next/link";
import { CaptureComposer } from "@/components/capture-composer";
import { Icon } from "@/components/icon";
import { PageFrame } from "@/components/page-frame";
import { ProgressiveImage } from "@/components/progressive-image";
import { greetingInTimezone } from "@/lib/data/home-input";
import {
  getHomeWorkspace,
  type HomeEntry,
  type HomeResurfacedMemory,
  type HomeSnapshot,
  type HomeStage,
  type HomeWorkspace,
} from "@/lib/data/home";
import styles from "./home.module.css";

export const dynamic = "force-dynamic";

export default async function HomePage() {
  const workspace = await getHomeWorkspace();

  if (!workspace) {
    return null;
  }

  return <HomeContent workspace={workspace} />;
}

function HomeContent({ workspace }: { workspace: HomeWorkspace }) {
  const now = new Date();
  const firstName = displayFirstName(
    workspace.snapshot?.profileDisplayName ?? workspace.viewer.name,
  );

  return (
    <PageFrame variant="wide">
      <header className={styles.pageHeader}>
        <div>
          <p className={styles.eyebrow}>
            {todayLabel(now, workspace.timezone)}
          </p>
          <h1>
            {greetingInTimezone(now, workspace.timezone)}, {firstName}.
          </h1>
          <p>A calm view of what is active, recent, and waiting for you.</p>
        </div>
        <Link className={styles.searchLink} href="/search">
          <Icon name="search" size={17} />
          <span>Search your trail</span>
        </Link>
      </header>

      <CaptureComposer ownerId={workspace.viewer.id} />

      {workspace.loadError || !workspace.snapshot ? (
        <section className={styles.message} role="alert">
          <Icon name="clock" size={22} />
          <div>
            <strong>Home is taking a moment</strong>
            <p>{workspace.loadError}</p>
          </div>
        </section>
      ) : (
        <HomeSnapshotContent
          resurfacedMemory={workspace.resurfacedMemory}
          snapshot={workspace.snapshot}
        />
      )}
    </PageFrame>
  );
}

function HomeSnapshotContent({
  resurfacedMemory,
  snapshot,
}: {
  resurfacedMemory: HomeResurfacedMemory | null;
  snapshot: HomeSnapshot;
}) {
  return (
    <>
      <section className={styles.todaySection} aria-labelledby="today-heading">
        <SectionHeading
          detail="The small signals that shape today"
          id="today-heading"
          title="Today"
        />
        <div className={styles.statGrid}>
          <HomeStat
            detail={entryLabel(snapshot.inboxCount, "Entry")}
            href="/inbox"
            icon="inbox"
            label="Waiting in Inbox"
            value={snapshot.inboxCount}
          />
          <HomeStat
            detail={entryLabel(snapshot.currentStageCount, "current chapter")}
            href="/timeline"
            icon="timeline"
            label="Life in progress"
            value={snapshot.currentStageCount}
          />
          <HomeStat
            detail={`${snapshot.firstTimeCount} First Times · ${snapshot.collectionCount} Collections`}
            href="/library"
            icon="archive"
            label="Entries kept"
            value={snapshot.entryCount}
          />
        </div>
      </section>

      <CurrentStages stages={snapshot.currentStages} />
      <ResurfacedMemory memory={resurfacedMemory} />
      <RecentEntries entries={snapshot.recentEntries} />
    </>
  );
}

function ResurfacedMemory({ memory }: { memory: HomeResurfacedMemory | null }) {
  if (!memory) {
    return null;
  }

  const cover = memory.attachments.find((attachment) => attachment.imageUrl);
  const context = [
    ...memory.collectionNames.map((name) => ({
      key: `collection:${name.toLocaleLowerCase()}`,
      label: name,
    })),
    ...memory.tagNames.map((tag) => ({
      key: `tag:${tag.toLocaleLowerCase()}`,
      label: `#${tag}`,
    })),
  ];

  return (
    <section className={styles.homeSection} aria-labelledby="memory-heading">
      <SectionHeading
        detail={resurfacingLabel(memory)}
        id="memory-heading"
        title="A memory for today"
      />
      <article
        className={`${styles.memoryCard} ${cover?.imageUrl ? "" : styles.memoryCardTextOnly}`}
      >
        {cover?.imageUrl ? (
          <ProgressiveImage
            alt={cover.originalFilename ?? "Memory photo"}
            className={styles.memoryImage}
            src={cover.imageUrl}
          />
        ) : null}
        <div>
          <header>
            <span>{entryTypeLabel(memory.entryType)}</span>
            <time dateTime={memory.occurredStart}>
              {entryDateLabel(memory)}
            </time>
          </header>
          <h3>{memory.title}</h3>
          {memory.body.trim() ? (
            <p>{truncate(memory.body.trim(), 240)}</p>
          ) : null}
          {context.length > 0 ? (
            <footer>
              {context.slice(0, 4).map((item) => (
                <span key={item.key}>{item.label}</span>
              ))}
            </footer>
          ) : null}
        </div>
      </article>
    </section>
  );
}

function HomeStat({
  detail,
  href,
  icon,
  label,
  value,
}: {
  detail: string;
  href: string;
  icon: "archive" | "check" | "inbox" | "timeline";
  label: string;
  value: number;
}) {
  return (
    <Link className={styles.statCard} href={href}>
      <span className={styles.statIcon}>
        <Icon name={icon} size={18} />
      </span>
      <span className={styles.statValue}>{value}</span>
      <strong>{label}</strong>
      <small>{detail}</small>
    </Link>
  );
}

function CurrentStages({ stages }: { stages: HomeStage[] }) {
  if (stages.length === 0) {
    return null;
  }

  return (
    <section className={styles.homeSection} aria-labelledby="chapters-heading">
      <SectionHeading
        actionHref="/timeline"
        actionLabel="Open Timeline"
        detail="The overlapping chapters you are living now"
        id="chapters-heading"
        title="Current chapters"
      />
      <div className={styles.stageGrid}>
        {stages.map((stage) => (
          <article
            className={styles.stageCard}
            key={`${stage.trackId}:${stage.entryId}`}
          >
            <span>{stage.trackName}</span>
            <h3>{stage.title}</h3>
            <p>{stageLabel(stage)}</p>
          </article>
        ))}
      </div>
    </section>
  );
}

function RecentEntries({ entries }: { entries: HomeEntry[] }) {
  return (
    <section className={styles.homeSection} aria-labelledby="recent-heading">
      <SectionHeading
        actionHref="/search"
        actionLabel="Search all"
        detail="The latest things added to your archive"
        id="recent-heading"
        title="Recent Entries"
      />

      {entries.length === 0 ? (
        <div className={styles.emptyState}>
          <Icon name="sparkle" size={22} />
          <div>
            <strong>Your trail starts here</strong>
            <p>
              Capture a thought above and it will become your first recent
              Entry.
            </p>
          </div>
        </div>
      ) : (
        <div className={styles.recentGrid}>
          {entries.map((entry) => (
            <RecentEntryCard entry={entry} key={entry.id} />
          ))}
        </div>
      )}
    </section>
  );
}

function RecentEntryCard({ entry }: { entry: HomeEntry }) {
  const cover = entry.attachments.find((attachment) => attachment.imageUrl);
  const context = [
    ...entry.collectionNames.map((name) => ({
      key: `collection:${name.toLocaleLowerCase()}`,
      label: name,
    })),
    ...entry.tagNames.map((tag) => ({
      key: `tag:${tag.toLocaleLowerCase()}`,
      label: `#${tag}`,
    })),
  ];

  return (
    <article
      className={`${styles.recentCard} ${cover?.imageUrl ? "" : styles.recentCardTextOnly}`}
    >
      {cover?.imageUrl ? (
        <ProgressiveImage
          alt={cover.originalFilename ?? "Entry photo"}
          className={styles.recentImage}
          src={cover.imageUrl}
        />
      ) : null}
      <div>
        <header>
          <span>{entryTypeLabel(entry.entryType)}</span>
          <time dateTime={entry.occurredStart ?? entry.createdAt}>
            {entryDateLabel(entry)}
          </time>
        </header>
        <h3>{entry.title}</h3>
        {entry.body.trim() ? <p>{truncate(entry.body.trim(), 170)}</p> : null}
        {context.length > 0 ? (
          <footer>
            {context.slice(0, 3).map((item) => (
              <span key={item.key}>{item.label}</span>
            ))}
          </footer>
        ) : null}
      </div>
    </article>
  );
}

function SectionHeading({
  actionHref,
  actionLabel,
  detail,
  id,
  title,
}: {
  actionHref?: string;
  actionLabel?: string;
  detail: string;
  id: string;
  title: string;
}) {
  return (
    <header className={styles.sectionHeading}>
      <div>
        <h2 id={id}>{title}</h2>
        <p>{detail}</p>
      </div>
      {actionHref && actionLabel ? (
        <Link href={actionHref}>
          {actionLabel}
          <Icon name="chevron" size={14} />
        </Link>
      ) : null}
    </header>
  );
}

function todayLabel(date: Date, timezone: string) {
  return new Intl.DateTimeFormat("en-US", {
    day: "numeric",
    month: "long",
    timeZone: timezone,
    weekday: "long",
  }).format(date);
}

function displayFirstName(name: string) {
  return name.trim().split(/\s+/)[0] || "MemoTrail";
}

function entryLabel(count: number, noun: string) {
  return `${count} ${count === 1 ? noun : `${noun}s`}`;
}

function stageLabel(stage: HomeStage) {
  if (stage.occurredLabel) {
    return stage.occurredLabel;
  }

  const start = formatDate(stage.occurredStart, stage.occurredTimezone);
  const end = stage.occurredEnd
    ? formatDate(stage.occurredEnd, stage.occurredTimezone)
    : "Present";
  return `${start} - ${end}`;
}

function entryDateLabel(entry: HomeEntry) {
  if (entry.occurredLabel) {
    return entry.occurredLabel;
  }

  return formatDate(
    entry.occurredStart ?? entry.createdAt,
    entry.occurredTimezone,
  );
}

function resurfacingLabel(memory: HomeResurfacedMemory) {
  if (memory.resurfacingKind === "on_this_day" && memory.yearsAgo) {
    return `On this day, ${memory.yearsAgo} ${memory.yearsAgo === 1 ? "year" : "years"} ago`;
  }

  return "A quiet note from your archive";
}

function formatDate(value: string, timezone: string | null) {
  try {
    return new Intl.DateTimeFormat("en-US", {
      day: "numeric",
      month: "short",
      timeZone: timezone ?? "UTC",
      year: "numeric",
    }).format(new Date(value));
  } catch {
    return new Intl.DateTimeFormat("en-US", {
      day: "numeric",
      month: "short",
      timeZone: "UTC",
      year: "numeric",
    }).format(new Date(value));
  }
}

function entryTypeLabel(type: string) {
  switch (type) {
    case "first_time":
      return "First Time";
    case "life_stage":
      return "Life Stage";
    default:
      return "Entry";
  }
}

function truncate(value: string, limit: number) {
  return value.length <= limit ? value : `${value.slice(0, limit).trimEnd()}…`;
}
