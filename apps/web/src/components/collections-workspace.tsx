import Link from "next/link";
import styles from "@/app/collections/page.module.css";
import { Icon } from "@/components/icon";
import { EntryRichTextContent } from "@/components/entry-rich-text-content";
import { OrganizationControl } from "@/components/organization-control";
import { PageFrame } from "@/components/page-frame";
import { ProgressiveImage } from "@/components/progressive-image";
import type {
  CollectionEntry,
  CollectionSummary,
  CollectionsWorkspace as CollectionsWorkspaceData,
} from "@/lib/data/collections";
import {
  COLLECTION_PAGE_SIZE,
  collectionPageHref,
} from "@/lib/data/collections-input";

export function CollectionsWorkspace({
  workspace,
}: {
  workspace: CollectionsWorkspaceData;
}) {
  const { selectedCollection } = workspace;

  return (
    <PageFrame variant="wide">
      <header className={styles.pageHeader}>
        <div>
          <p className={styles.eyebrow}>
            {selectedCollection ? "Collection archive" : "Browse by meaning"}
          </p>
          <h1>{selectedCollection?.name ?? "Collections"}</h1>
          <p>
            {selectedCollection
              ? "Entries can belong to more than one Collection without being copied or separated."
              : "Open a theme to revisit the Entries, moments, and firsts you filed together."}
          </p>
        </div>
        {selectedCollection ? (
          <Link className={styles.newEntryButton} href="/inbox#capture-title">
            <Icon name="plus" />
            <span>New entry</span>
          </Link>
        ) : (
          <OrganizationControl
            items={workspace.organizationItems}
            kind="collection"
          />
        )}
      </header>

      {selectedCollection ? (
        <CollectionDetail workspace={workspace} />
      ) : (
        <CollectionOverview workspace={workspace} />
      )}
    </PageFrame>
  );
}

function CollectionOverview({
  workspace,
}: {
  workspace: CollectionsWorkspaceData;
}) {
  if (workspace.loadError) {
    return (
      <CollectionMessage
        message={workspace.loadError}
        title="Collections unavailable"
      />
    );
  }

  if (workspace.collections.length === 0) {
    return (
      <div className={styles.emptyState}>
        <span className={styles.emptyMark}>
          <Icon name="archive" size={23} />
        </span>
        <strong>No Collections yet</strong>
        <p>
          Add a Collection while organizing an Inbox Entry or saving a First
          Time. It will appear here automatically.
        </p>
        <Link href="/inbox">Open Inbox</Link>
      </div>
    );
  }

  const placementCount = workspace.collections.reduce(
    (total, collection) => total + collection.entryCount,
    0,
  );

  return (
    <>
      <div className={styles.summary} aria-label="Collections summary">
        <span>{countLabel(workspace.collections.length, "Collection")}</span>
        <span aria-hidden="true">·</span>
        <span>{countLabel(placementCount, "Entry placement")}</span>
      </div>

      <section className={styles.collectionGrid} aria-label="Collections">
        {workspace.collections.map((collection, index) => (
          <CollectionCard
            collection={collection}
            index={index + 1}
            key={collection.id}
            organizationItem={workspace.organizationItems.find(
              (item) => item.id === collection.id,
            )}
            organizationItems={workspace.organizationItems}
          />
        ))}
      </section>
    </>
  );
}

function CollectionCard({
  collection,
  index,
  organizationItem,
  organizationItems,
}: {
  collection: CollectionSummary;
  index: number;
  organizationItem:
    CollectionsWorkspaceData["organizationItems"][number] | undefined;
  organizationItems: CollectionsWorkspaceData["organizationItems"];
}) {
  return (
    <article className={styles.collectionCard}>
      <Link className={styles.cardLink} href={`/collections/${collection.id}`}>
        <div className={styles.cardTopline}>
          <span>{String(index).padStart(2, "0")}</span>
          <Icon name="archive" size={20} />
        </div>
        <h2>{collection.name}</h2>
        <p>
          {collection.entryCount === 0
            ? "Ready for its first Entry."
            : `${countLabel(collection.entryCount, "Entry")} filed here.`}
        </p>
        <footer>
          <span>
            {collection.latestEntryAt
              ? `Latest ${shortDate(collection.latestEntryAt)}`
              : "Empty Collection"}
          </span>
          {collection.unreviewedCount ? (
            <strong>{collection.unreviewedCount} in Inbox</strong>
          ) : (
            <Icon name="chevron" size={16} />
          )}
        </footer>
      </Link>
      {organizationItem ? (
        <div className={styles.cardControl}>
          <OrganizationControl
            item={organizationItem}
            items={organizationItems}
            kind="collection"
          />
        </div>
      ) : null}
    </article>
  );
}

function CollectionDetail({
  workspace,
}: {
  workspace: CollectionsWorkspaceData;
}) {
  const collection = workspace.selectedCollection;

  if (!collection) {
    return (
      <CollectionMessage
        message={workspace.loadError ?? "Refresh to try again."}
        title="Collection unavailable"
      />
    );
  }

  return (
    <>
      <div className={styles.detailToolbar}>
        <Link href="/collections">
          <span aria-hidden="true">←</span>
          All Collections
        </Link>
        <div aria-label="Collection summary">
          <span>{countLabel(collection.entryCount, "Entry")}</span>
          {collection.unreviewedCount ? (
            <span>{collection.unreviewedCount} still in Inbox</span>
          ) : null}
        </div>
        {workspace.organizationItems.find(
          (item) => item.id === collection.id,
        ) ? (
          <OrganizationControl
            item={workspace.organizationItems.find(
              (item) => item.id === collection.id,
            )}
            items={workspace.organizationItems}
            kind="collection"
          />
        ) : null}
      </div>

      {workspace.detailLoadError ? (
        <CollectionMessage
          message={workspace.detailLoadError}
          title="Collection unavailable"
        />
      ) : workspace.entries.length === 0 ? (
        <div className={styles.emptyState}>
          <span className={styles.emptyMark}>
            <Icon name="archive" size={23} />
          </span>
          <strong>This Collection is empty</strong>
          <p>
            Assign “{collection.name}” while organizing an Entry and it will
            appear here.
          </p>
          <Link href="/inbox">Open Inbox</Link>
        </div>
      ) : (
        <section
          className={styles.entryList}
          aria-label={`${collection.name} Entries`}
        >
          {workspace.entries.map((entry) => (
            <CollectionEntryCard entry={entry} key={entry.id} />
          ))}
        </section>
      )}

      <CollectionPagination
        collectionId={collection.id}
        page={workspace.page}
        totalCount={workspace.totalCount}
      />
    </>
  );
}

function CollectionEntryCard({ entry }: { entry: CollectionEntry }) {
  const body = entry.body.trim();
  const title = entry.title ?? firstUsefulLine(body) ?? "Untitled Entry";
  const cover = entry.attachments.find(
    (attachment) => attachment.variant === "original",
  );

  return (
    <article className={styles.entryCard}>
      {cover ? (
        <div className={styles.entryCover}>
          {cover.imageUrl ? (
            <ProgressiveImage
              alt={cover.originalFilename ?? "Entry photo"}
              src={cover.imageUrl}
            />
          ) : (
            <span className={styles.entryCoverFallback}>
              <Icon name="photo" size={22} />
              Private photo
            </span>
          )}
        </div>
      ) : null}

      <div className={styles.entryContent}>
        <header>
          <div className={styles.entryMeta}>
            <span>{entryTypeLabel(entry.entryType)}</span>
            {entry.inboxStatus === "unreviewed" ? <span>In Inbox</span> : null}
            <time dateTime={entry.occurredStart ?? entry.updatedAt}>
              {entryDateLabel(entry)}
            </time>
          </div>
          <h2>{title}</h2>
        </header>

        {body ? (
          <EntryRichTextContent
            body={body}
            className={styles.entryBody}
            richText={entry.bodyRich}
          />
        ) : null}

        {body.length > 320 ? (
          <details className={styles.fullEntry}>
            <summary>Read full note</summary>
            <EntryRichTextContent
              body={body}
              className={styles.fullEntryBody}
              richText={entry.bodyRich}
            />
          </details>
        ) : null}

        {entry.collectionNames.length || entry.tagNames.length ? (
          <div className={styles.organization} aria-label="Entry organization">
            {entry.collectionNames.map((name) => (
              <Link
                href={`/search?collection=${encodeURIComponent(name)}`}
                key={`collection:${name.toLocaleLowerCase()}`}
              >
                <Icon name="archive" size={12} />
                {name}
              </Link>
            ))}
            {entry.tagNames.map((name) => (
              <Link
                href={`/search?tag=${encodeURIComponent(name)}`}
                key={`tag:${name.toLocaleLowerCase()}`}
              >
                #{name}
              </Link>
            ))}
          </div>
        ) : null}
      </div>
    </article>
  );
}

function CollectionPagination({
  collectionId,
  page,
  totalCount,
}: {
  collectionId: string;
  page: number;
  totalCount: number;
}) {
  const hasPrevious = page > 1;
  const hasNext = page * COLLECTION_PAGE_SIZE < totalCount;

  if (!hasPrevious && !hasNext) {
    return null;
  }

  return (
    <nav className={styles.pagination} aria-label="Collection Entry pages">
      {hasPrevious ? (
        <Link href={collectionPageHref(collectionId, page - 1)}>Previous</Link>
      ) : (
        <span />
      )}
      <span>Page {page}</span>
      {hasNext ? (
        <Link href={collectionPageHref(collectionId, page + 1)}>Next</Link>
      ) : (
        <span />
      )}
    </nav>
  );
}

function CollectionMessage({
  message,
  title,
}: {
  message: string;
  title: string;
}) {
  return (
    <div className={styles.message} role="alert">
      <Icon name="archive" size={23} />
      <div>
        <strong>{title}</strong>
        <p>{message}</p>
      </div>
    </div>
  );
}

function entryDateLabel(entry: CollectionEntry) {
  if (entry.occurredLabel) {
    return entry.occurredLabel;
  }

  if (!entry.occurredStart) {
    return "Date not set";
  }

  const start = formatEntryDate(
    entry.occurredStart,
    entry.datePrecision,
    entry.occurredTimezone,
  );
  const end = entry.occurredEnd
    ? formatEntryDate(
        entry.occurredEnd,
        entry.datePrecision,
        entry.occurredTimezone,
      )
    : null;

  return end ? `${start} - ${end}` : start;
}

function formatEntryDate(
  value: string,
  precision: string,
  timeZone: string | null,
) {
  const options: Intl.DateTimeFormatOptions =
    precision === "year"
      ? { year: "numeric" }
      : precision === "month"
        ? { month: "short", year: "numeric" }
        : { day: "numeric", month: "short", year: "numeric" };

  try {
    return new Intl.DateTimeFormat("en-US", {
      ...options,
      timeZone: timeZone ?? "UTC",
    }).format(new Date(value));
  } catch {
    return new Intl.DateTimeFormat("en-US", {
      ...options,
      timeZone: "UTC",
    }).format(new Date(value));
  }
}

function entryTypeLabel(value: string) {
  const labels: Record<string, string> = {
    first_time: "First Time",
    goal: "Goal",
    home: "Home",
    life_stage: "Life Stage",
    standard: "Standard Entry",
    vehicle: "Vehicle",
  };

  return (
    labels[value] ??
    value
      .split("_")
      .filter(Boolean)
      .map((part) => `${part.charAt(0).toLocaleUpperCase()}${part.slice(1)}`)
      .join(" ")
  );
}

function firstUsefulLine(value: string) {
  return value
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find(Boolean);
}

function countLabel(count: number, singular: string) {
  return `${count} ${count === 1 ? singular : `${singular}s`}`;
}

function shortDate(value: string) {
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    year: "numeric",
  }).format(new Date(value));
}
