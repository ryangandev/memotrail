import { EmptyState } from "@/components/empty-state";
import { PageHeader } from "@/components/page-header";
import { ButtonLink } from "@/components/button";
import Link from "next/link";
import styles from "@/components/collections-workspace.module.css";
import { Icon } from "@/components/icon";
import { Badge } from "@/components/badge";
import { EntryRichTextContent } from "@/components/entry-rich-text-content";
import { OrganizationControl } from "@/components/organization-control";
import { PageFrame } from "@/components/page-frame";
import { CollectionCard } from "@/components/collection-card";
import { ProgressiveImage } from "@/components/progressive-image";
import { SeparatedList } from "@/components/separated-list";
import type {
  CollectionEntry,
  CollectionsWorkspace as CollectionsWorkspaceData,
} from "@/lib/data/collections";
import {
  COLLECTION_PAGE_SIZE,
  collectionPageHref,
} from "@/lib/data/collections-input";
import { wikiEntryHref, wikiItemIdentityLabel } from "@/lib/data/wiki-item";
import { countLabel } from "@/lib/count-label";

export function CollectionsWorkspace({
  workspace,
}: {
  workspace: CollectionsWorkspaceData;
}) {
  const { selectedCollection } = workspace;

  return (
    <PageFrame variant="wide">
      <PageHeader
        title={<>{selectedCollection?.name ?? "Collections"}</>}
        eyebrow={
          <>{selectedCollection ? "Collection archive" : "Browse by meaning"}</>
        }
        description={
          <>
            {selectedCollection
              ? "Entries can belong to more than one Collection without being copied or separated."
              : "Open a theme to revisit the Entries, moments, and firsts you filed together."}
          </>
        }
        actions={
          <>
            {selectedCollection ? (
              <ButtonLink href="/inbox#capture-title">
                <Icon name="plus" />
                <span>New entry</span>
              </ButtonLink>
            ) : (
              <OrganizationControl
                items={workspace.organizationItems}
                kind="collection"
              />
            )}
          </>
        }
      />

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
      <EmptyState
        title={<>No Collections yet</>}
        icon={
          <>
            <Icon name="archive" size={23} />
          </>
        }
        description={
          <>
            Add a Collection while organizing an Inbox Entry or saving a First
            Time. It will appear here automatically.
          </>
        }
        actions={
          <>
            <Link href="/inbox">Open Inbox</Link>
          </>
        }
      />
    );
  }

  const placementCount = workspace.collections.reduce(
    (total, collection) => total + collection.entryCount,
    0,
  );

  return (
    <>
      <div className={styles.summary} aria-label="Collections summary">
        <SeparatedList>
          <span>{countLabel(workspace.collections.length, "Collection")}</span>
          <span>{countLabel(placementCount, "Entry placement")}</span>
        </SeparatedList>
      </div>

      <section className={styles.collectionGrid} aria-label="Collections">
        {workspace.collections.map((collection) => {
          const organizationItem = workspace.organizationItems.find(
            (item) => item.id === collection.id,
          );
          return (
            <CollectionCard
              entryCount={collection.entryCount}
              href={`/collections/${collection.id}`}
              inboxCount={collection.unreviewedCount}
              key={collection.id}
              manageAction={
                organizationItem ? (
                  <OrganizationControl
                    item={organizationItem}
                    items={workspace.organizationItems}
                    kind="collection"
                  />
                ) : null
              }
              name={collection.name}
              updatedLabel={
                collection.latestEntryAt
                  ? `Latest ${shortDate(collection.latestEntryAt)}`
                  : undefined
              }
            />
          );
        })}
      </section>
    </>
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
          <SeparatedList>
            <span>{countLabel(collection.entryCount, "Entry")}</span>
            {collection.unreviewedCount ? (
              <span>{collection.unreviewedCount} still in Inbox</span>
            ) : null}
          </SeparatedList>
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
        <EmptyState
          title={<>This Collection is empty</>}
          icon={
            <>
              <Icon name="archive" size={23} />
            </>
          }
          description={
            <>
              Assign “{collection.name}” while organizing an Entry and it will
              appear here.
            </>
          }
          actions={
            <>
              <Link href="/inbox">Open Inbox</Link>
            </>
          }
        />
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
            <Badge tone="neutral">
              {wikiItemIdentityLabel(entry.itemKind, entry.itemSubtype)}
            </Badge>
            {entry.inboxStatus === "unreviewed" ? (
              <Badge tone="warm">In Inbox</Badge>
            ) : null}
            <time dateTime={entry.occurredStart ?? entry.updatedAt}>
              {entryDateLabel(entry)}
            </time>
          </div>
          <h2>
            <Link href={wikiEntryHref(entry)}>{title}</Link>
          </h2>
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
                href={`/library?collection=${encodeURIComponent(name)}`}
                key={`collection:${name.toLocaleLowerCase()}`}
              >
                <Icon name="archive" size={12} />
                {name}
              </Link>
            ))}
            {entry.tagNames.map((name) => (
              <Link
                href={`/library?tag=${encodeURIComponent(name)}`}
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

function firstUsefulLine(value: string) {
  return value
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find(Boolean);
}

function shortDate(value: string) {
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    year: "numeric",
  }).format(new Date(value));
}
