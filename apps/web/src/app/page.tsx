import { Icon, type IconName } from "@/components/icon";
import { AuthGate } from "@/components/auth-gate";
import { CaptureComposer } from "@/components/capture-composer";
import { SyncStatus } from "@/components/sync-status";
import { EntryReviewList } from "@/components/entry-review-list";
import { signOut } from "@/app/auth/actions";
import {
  getInboxWorkspace,
  type InboxEntry,
  type Viewer,
} from "@/lib/data/inbox";
import { getSupabasePublicConfig } from "@/lib/supabase/config";
import styles from "./page.module.css";

export const dynamic = "force-dynamic";

type NavigationItem = {
  active?: boolean;
  count?: number;
  icon: IconName;
  label: string;
};

const primaryNavigation: NavigationItem[] = [
  { icon: "inbox", label: "Inbox", active: true },
  { icon: "timeline", label: "Timeline" },
  { icon: "star", label: "First Times" },
  { icon: "archive", label: "Collections" },
];

const recordNavigation: NavigationItem[] = [
  { icon: "check", label: "Habits" },
  { icon: "map", label: "Places" },
  { icon: "car", label: "Vehicles" },
];

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
  const navigation = navigationWithInboxCount(entries.length);

  return (
    <div className={styles.appShell}>
      <Sidebar navigation={navigation} viewer={viewer} />

      <main className={styles.workspace}>
        <header className={styles.topBar}>
          <div className={styles.mobileBrand} aria-label="MemoTrail home">
            <span className={styles.brandMark}>M</span>
            <span>MemoTrail</span>
          </div>

          <button className={styles.searchButton} type="button">
            <Icon name="search" />
            <span>Search your trail</span>
            <kbd>⌘ K</kbd>
          </button>

          <div className={styles.topActions}>
            <SyncStatus ownerId={viewer.id} />
            <form action={signOut}>
              <button
                className={styles.avatarButton}
                type="submit"
                aria-label={`Sign out ${viewer.name}`}
              >
                {viewer.initial}
              </button>
            </form>
          </div>
        </header>

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
      </main>

      <nav className={styles.mobileNavigation} aria-label="Mobile navigation">
        {navigation.map((item) => (
          <button
            className={item.active ? styles.mobileActive : undefined}
            key={item.label}
            type="button"
          >
            <Icon name={item.icon} size={20} />
            <span>{item.label === "First Times" ? "Firsts" : item.label}</span>
          </button>
        ))}
      </nav>
    </div>
  );
}

function Sidebar({
  navigation,
  viewer,
}: {
  navigation: NavigationItem[];
  viewer: Viewer;
}) {
  return (
    <aside className={styles.sidebar}>
      <div className={styles.brand}>
        <span className={styles.brandMark}>M</span>
        <span>MemoTrail</span>
      </div>

      <nav className={styles.sidebarNav} aria-label="Primary navigation">
        <NavGroup items={navigation} />
        <div className={styles.navDivider} />
        <p className={styles.navLabel}>Records</p>
        <NavGroup items={recordNavigation} />
      </nav>

      <div className={styles.sidebarFooter}>
        <div className={styles.archiveNote}>
          <Icon name="clock" size={17} />
          <div>
            <strong>Private cloud sync</strong>
            <span>Available on Web and iPhone</span>
          </div>
        </div>
        <form action={signOut}>
          <button type="submit" title={`Sign out ${viewer.email}`}>
            <span className={styles.avatar}>{viewer.initial}</span>
            <span>
              <strong>{viewer.name}</strong>
              <small>Sign out · Private space</small>
            </span>
            <Icon name="more" size={17} />
          </button>
        </form>
      </div>
    </aside>
  );
}

function NavGroup({ items }: { items: NavigationItem[] }) {
  return (
    <div className={styles.navGroup}>
      {items.map((item) => (
        <button
          className={item.active ? styles.activeNavItem : undefined}
          key={item.label}
          type="button"
        >
          <Icon name={item.icon} />
          <span>{item.label}</span>
          {item.count ? <small>{item.count}</small> : null}
        </button>
      ))}
    </div>
  );
}

function navigationWithInboxCount(count: number) {
  return primaryNavigation.map((item) =>
    item.label === "Inbox" ? { ...item, count } : item,
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
