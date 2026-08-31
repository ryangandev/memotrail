import { Icon, type IconName } from "@/components/icon";
import { AuthGate } from "@/components/auth-gate";
import { signOut } from "@/app/auth/actions";
import { getSupabasePublicConfig } from "@/lib/supabase/config";
import { createClient } from "@/lib/supabase/server";
import styles from "./page.module.css";

export const dynamic = "force-dynamic";

type NavigationItem = {
  active?: boolean;
  count?: number;
  icon: IconName;
  label: string;
};

const primaryNavigation: NavigationItem[] = [
  { icon: "inbox", label: "Inbox", count: 4, active: true },
  { icon: "timeline", label: "Timeline" },
  { icon: "star", label: "First Times" },
  { icon: "archive", label: "Collections" },
];

const recordNavigation: NavigationItem[] = [
  { icon: "check", label: "Habits" },
  { icon: "map", label: "Places" },
  { icon: "car", label: "Vehicles" },
];

const entries = [
  {
    date: "Today, 9:42 AM",
    title: "Why do people need to keep learning?",
    excerpt:
      "Maybe learning is less about collecting answers and more about keeping our model of the world alive.",
    tags: ["reflection", "learning"],
    suggested: true,
  },
  {
    date: "Yesterday, 8:16 PM",
    title: "How clear aligners move teeth",
    excerpt:
      "Small, controlled forces trigger bone remodeling around each tooth. The bone changes rather than the tooth bending.",
    tags: ["learned", "health"],
    suggested: true,
  },
  {
    date: "Jul 3, 2026",
    title: "First time skiing",
    excerpt:
      "Fell more times than I can count, then finally linked three turns together before the last run.",
    tags: ["first time", "travel"],
    suggested: false,
  },
];

type Viewer = {
  email: string;
  initial: string;
  name: string;
};

export default async function Home() {
  const isConfigured = Boolean(getSupabasePublicConfig());

  if (!isConfigured) {
    return <AuthGate configured={false} />;
  }

  const viewer = await getViewer();

  if (!viewer) {
    return <AuthGate configured />;
  }

  return <Workspace viewer={viewer} />;
}

function Workspace({ viewer }: { viewer: Viewer }) {
  return (
    <div className={styles.appShell}>
      <Sidebar viewer={viewer} />

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
            <span className={styles.syncStatus}>
              <span /> Saved
            </span>
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
              <p className={styles.eyebrow}>Sunday, August 30</p>
              <h1>Inbox</h1>
              <p>Capture now. Make sense of it when you are ready.</p>
            </div>
            <button className={styles.newEntryButton} type="button">
              <Icon name="plus" />
              <span>New entry</span>
            </button>
          </header>

          <section
            className={styles.captureCard}
            aria-labelledby="capture-heading"
          >
            <div className={styles.captureIntro}>
              <span className={styles.captureSpark}>
                <Icon name="sparkle" size={19} />
              </span>
              <div>
                <h2 id="capture-heading">What is worth keeping?</h2>
                <p>
                  A thought, a first, something learned, or whatever is on your
                  mind.
                </p>
              </div>
            </div>
            <div className={styles.captureActions}>
              <div>
                <button className={styles.quietButton} type="button">
                  <Icon name="mic" /> Voice
                </button>
                <button className={styles.quietButton} type="button">
                  <Icon name="photo" /> Photo
                </button>
              </div>
              <button className={styles.saveButton} type="button">
                Save to Inbox
                <Icon name="chevron" size={16} />
              </button>
            </div>
          </section>

          <section
            className={styles.entrySection}
            aria-labelledby="recent-heading"
          >
            <div className={styles.sectionHeader}>
              <div>
                <h2 id="recent-heading">Unsorted</h2>
                <span>4 entries</span>
              </div>
              <button type="button">Select</button>
            </div>

            <div className={styles.entryList}>
              {entries.map((entry) => (
                <article className={styles.entryCard} key={entry.title}>
                  <div className={styles.entryMeta}>
                    <time>{entry.date}</time>
                    <button
                      type="button"
                      aria-label={`More actions for ${entry.title}`}
                    >
                      <Icon name="more" />
                    </button>
                  </div>
                  <h3>{entry.title}</h3>
                  <p>{entry.excerpt}</p>
                  <footer>
                    <div className={styles.tags}>
                      {entry.tags.map((tag) => (
                        <span key={tag}>{tag}</span>
                      ))}
                    </div>
                    {entry.suggested ? (
                      <span className={styles.aiLabel}>
                        <Icon name="sparkle" size={13} /> AI suggested
                      </span>
                    ) : null}
                  </footer>
                </article>
              ))}

              <button className={styles.moreEntries} type="button">
                Show 1 more entry
              </button>
            </div>
          </section>
        </div>
      </main>

      <nav className={styles.mobileNavigation} aria-label="Mobile navigation">
        {primaryNavigation.map((item) => (
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

function Sidebar({ viewer }: { viewer: Viewer }) {
  return (
    <aside className={styles.sidebar}>
      <div className={styles.brand}>
        <span className={styles.brandMark}>M</span>
        <span>MemoTrail</span>
      </div>

      <nav className={styles.sidebarNav} aria-label="Primary navigation">
        <NavGroup items={primaryNavigation} />
        <div className={styles.navDivider} />
        <p className={styles.navLabel}>Records</p>
        <NavGroup items={recordNavigation} />
      </nav>

      <div className={styles.sidebarFooter}>
        <div className={styles.archiveNote}>
          <Icon name="clock" size={17} />
          <div>
            <strong>12 years recorded</strong>
            <span>Your trail keeps growing</span>
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

async function getViewer(): Promise<Viewer | null> {
  try {
    const supabase = await createClient();
    const { data, error } = await supabase.auth.getClaims();

    if (error || !data?.claims) {
      return null;
    }

    const claims = data.claims as Record<string, unknown>;
    const metadata = asRecord(claims.user_metadata);
    const email = stringValue(claims.email) ?? "Signed-in account";
    const name =
      stringValue(metadata.full_name) ??
      stringValue(metadata.name) ??
      email.split("@")[0] ??
      "MemoTrail";
    const initial = name.trim().charAt(0).toLocaleUpperCase() || "M";

    return { email, initial, name };
  } catch {
    return null;
  }
}

function asRecord(value: unknown): Record<string, unknown> {
  if (typeof value === "object" && value !== null) {
    return value as Record<string, unknown>;
  }

  return {};
}

function stringValue(value: unknown) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}
