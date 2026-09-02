import { AuthGate } from "@/components/auth-gate";
import { CaptureComposer } from "@/components/capture-composer";
import { EntryReviewList } from "@/components/entry-review-list";
import { Icon } from "@/components/icon";
import { WorkspaceShell } from "@/components/workspace-shell";
import {
  getInboxWorkspace,
  type InboxEntry,
  type Viewer,
} from "@/lib/data/inbox";
import { getSupabasePublicConfig } from "@/lib/supabase/config";
import styles from "./page.module.css";

export const dynamic = "force-dynamic";

export default async function Home() {
  const isConfigured = Boolean(getSupabasePublicConfig());

  if (!isConfigured) {
    return <AuthGate configured={false} />;
  }

  const workspace = await getInboxWorkspace();

  if (!workspace) {
    return <AuthGate configured />;
  }

  return <Workspace {...workspace} />;
}

function Workspace({
  collectionOptions,
  entries,
  loadError,
  tagOptions,
  viewer,
}: {
  collectionOptions: string[];
  entries: InboxEntry[];
  loadError: string | null;
  tagOptions: string[];
  viewer: Viewer;
}) {
  return (
    <WorkspaceShell
      activeDestination="inbox"
      inboxCount={entries.length}
      viewer={viewer}
    >
      <div className={styles.content}>
        <header className={styles.pageHeader}>
          <div>
            <p className={styles.eyebrow}>{todayLabel()}</p>
            <h1>Inbox</h1>
            <p>Capture now. Make sense of it when you are ready.</p>
          </div>
          <a className={styles.newEntryButton} href="#capture-title">
            <Icon name="plus" />
            <span>New entry</span>
          </a>
        </header>

        <CaptureComposer ownerId={viewer.id} />

        <section
          className={styles.entrySection}
          aria-labelledby="recent-heading"
        >
          <div className={styles.sectionHeader}>
            <div>
              <h2 id="recent-heading">Unsorted</h2>
              <span>{entryCountLabel(entries.length)}</span>
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
                  <p>Save a thought above and it will appear here.</p>
                </div>
              </div>
            ) : null}

            <EntryReviewList
              collectionOptions={collectionOptions}
              entries={entries}
              tagOptions={tagOptions}
            />
          </div>
        </section>
      </div>
    </WorkspaceShell>
  );
}

function todayLabel() {
  return new Intl.DateTimeFormat("en-US", {
    day: "numeric",
    month: "long",
    weekday: "long",
  }).format(new Date());
}

function entryCountLabel(count: number) {
  return `${count} ${count === 1 ? "entry" : "entries"}`;
}
