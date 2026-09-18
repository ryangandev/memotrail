import { PageHeader } from "@/components/page-header";
import { EntryReviewList } from "@/components/entry-review-list";
import { Icon } from "@/components/icon";
import { PageFrame } from "@/components/page-frame";
import { getInboxWorkspace, type InboxEntry } from "@/lib/data/inbox";
import styles from "../page.module.css";

export const dynamic = "force-dynamic";

export default async function InboxPage({
  searchParams,
}: {
  searchParams: Promise<{ entry?: string | string[] }>;
}) {
  const parameters = await searchParams;
  const requestedEntry = Array.isArray(parameters.entry)
    ? parameters.entry[0]
    : parameters.entry;
  const focusedEntryId = validEntryID(requestedEntry) ? requestedEntry : null;
  const workspace = await getInboxWorkspace(focusedEntryId);

  if (!workspace) {
    return null;
  }

  return <Workspace {...workspace} focusedEntryId={focusedEntryId} />;
}

function Workspace({
  collectionOptions,
  entries,
  loadError,
  tagOptions,
  focusedEntryId,
}: {
  collectionOptions: string[];
  entries: InboxEntry[];
  focusedEntryId: string | null;
  loadError: string | null;
  tagOptions: string[];
}) {
  return (
    <PageFrame variant="compact">
      <PageHeader
        title={<>Inbox</>}
        eyebrow={<>{todayLabel()}</>}
        description={<>Review and organize the captures waiting for a place.</>}
      />

      <section className={styles.entrySection} aria-labelledby="recent-heading">
        <div className={styles.sectionHeader}>
          <div>
            <h2 id="recent-heading">Ready to organize</h2>
            <span>{captureCountLabel(entries.length)}</span>
          </div>
        </div>

        <div className={styles.entryList}>
          {loadError ? (
            <div className={styles.inboxMessage} role="alert">
              <Icon name="clock" size={20} />
              <div>
                <strong>Inbox unavailable</strong>
                <p>{loadError}</p>
              </div>
            </div>
          ) : null}

          {!loadError && entries.length === 0 ? (
            <div className={styles.inboxMessage}>
              <Icon name="inbox" size={22} />
              <div>
                <strong>Your Inbox is ready</strong>
                <p>New captures will wait here until you give them a place.</p>
              </div>
            </div>
          ) : null}

          <EntryReviewList
            collectionOptions={collectionOptions}
            entries={entries}
            initialEntryID={focusedEntryId}
            key={focusedEntryId ?? "inbox"}
            tagOptions={tagOptions}
          />
        </div>
      </section>
    </PageFrame>
  );
}

function todayLabel() {
  return new Intl.DateTimeFormat("en-US", {
    day: "numeric",
    month: "long",
    weekday: "long",
  }).format(new Date());
}

function captureCountLabel(count: number) {
  return `${count} ${count === 1 ? "capture" : "captures"}`;
}

function validEntryID(value: unknown): value is string {
  return (
    typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value,
    )
  );
}
