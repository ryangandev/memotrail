import Link from "next/link";
import type { ReactNode } from "react";
import { signOut } from "@/app/auth/actions";
import styles from "@/app/page.module.css";
import { Icon, type IconName } from "@/components/icon";
import { QuickCaptureDialog } from "@/components/quick-capture-dialog";
import { SearchShortcutLink } from "@/components/search-shortcut-link";
import { SyncStatus } from "@/components/sync-status";
import { TimezoneSync } from "@/components/timezone-sync";
import type { Viewer } from "@/lib/data/inbox";

export type WorkspaceDestination =
  | "collections"
  | "habits"
  | "home"
  | "homes"
  | "inbox"
  | "library"
  | "places"
  | "search"
  | "timeline"
  | "trash"
  | "vehicles"
  | "first-times";

type NavigationItem = {
  destination: WorkspaceDestination;
  href?: string;
  icon: IconName;
  label: string;
};

const primaryNavigation: NavigationItem[] = [
  { destination: "home", href: "/", icon: "home", label: "Home" },
  { destination: "search", href: "/search", icon: "search", label: "Search" },
  { destination: "inbox", href: "/inbox", icon: "inbox", label: "Inbox" },
  {
    destination: "timeline",
    href: "/timeline",
    icon: "timeline",
    label: "Timeline",
  },
];

const recordNavigation: NavigationItem[] = [
  { destination: "habits", href: "/habits", icon: "check", label: "Habits" },
  { destination: "homes", href: "/homes", icon: "home", label: "Homes" },
  { destination: "places", icon: "map", label: "Places" },
  { destination: "vehicles", icon: "car", label: "Vehicles" },
];

const archiveNavigation: NavigationItem[] = [
  {
    destination: "first-times",
    href: "/first-times",
    icon: "star",
    label: "First Times",
  },
  {
    destination: "collections",
    href: "/collections",
    icon: "archive",
    label: "Collections",
  },
  { destination: "trash", href: "/trash", icon: "trash", label: "Trash" },
];

const mobileNavigation: NavigationItem[] = [
  { destination: "home", href: "/", icon: "home", label: "Home" },
  { destination: "inbox", href: "/inbox", icon: "inbox", label: "Inbox" },
  {
    destination: "timeline",
    href: "/timeline",
    icon: "timeline",
    label: "Timeline",
  },
  { destination: "habits", href: "/habits", icon: "check", label: "Habits" },
  {
    destination: "library",
    href: "/library",
    icon: "archive",
    label: "Library",
  },
];

export function WorkspaceShell({
  activeDestination,
  children,
  inboxCount,
  viewer,
}: {
  activeDestination: WorkspaceDestination;
  children: ReactNode;
  inboxCount?: number;
  viewer: Viewer;
}) {
  return (
    <div className={styles.appShell}>
      <TimezoneSync />
      <Sidebar
        activeDestination={activeDestination}
        inboxCount={inboxCount}
        viewer={viewer}
      />

      <main className={styles.workspace}>
        <header className={styles.topBar}>
          <Link
            className={styles.mobileBrand}
            href="/"
            aria-label="MemoTrail home"
          >
            <span className={styles.brandMark}>M</span>
            <span>MemoTrail</span>
          </Link>

          <SearchShortcutLink
            active={activeDestination === "search"}
            className={styles.searchButton}
          />

          <div className={styles.topActions}>
            <SyncStatus ownerId={viewer.id} />
            <div className={styles.mobileCaptureButton}>
              <CaptureControl
                activeDestination={activeDestination}
                compact
                idPrefix="mobile-capture"
                ownerId={viewer.id}
              />
            </div>
            <Link
              aria-current={activeDestination === "trash" ? "page" : undefined}
              aria-label="Open Trash"
              className={styles.mobileTrashButton}
              href="/trash"
            >
              <Icon name="trash" size={19} />
            </Link>
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

        {children}
      </main>

      <nav className={styles.mobileNavigation} aria-label="Mobile navigation">
        {mobileNavigation.map((item) => (
          <NavigationControl
            active={isNavigationActive(item, activeDestination)}
            inboxCount={item.destination === "inbox" ? inboxCount : undefined}
            item={item}
            key={item.destination}
            mobile
          />
        ))}
      </nav>
    </div>
  );
}

function Sidebar({
  activeDestination,
  inboxCount,
  viewer,
}: {
  activeDestination: WorkspaceDestination;
  inboxCount?: number;
  viewer: Viewer;
}) {
  return (
    <aside className={styles.sidebar}>
      <Link className={styles.brand} href="/">
        <span className={styles.brandMark}>M</span>
        <span>MemoTrail</span>
      </Link>

      <div className={styles.sidebarCaptureButton}>
        <CaptureControl
          activeDestination={activeDestination}
          idPrefix="sidebar-capture"
          ownerId={viewer.id}
        />
      </div>

      <nav className={styles.sidebarNav} aria-label="Primary navigation">
        <NavGroup
          activeDestination={activeDestination}
          inboxCount={inboxCount}
          items={primaryNavigation}
        />
        <div className={styles.navDivider} />
        <p className={styles.navLabel}>Records</p>
        <NavGroup
          activeDestination={activeDestination}
          items={recordNavigation}
        />
        <div className={styles.navDivider} />
        <p className={styles.navLabel}>Library</p>
        <NavGroup
          activeDestination={activeDestination}
          items={archiveNavigation}
        />
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

function NavGroup({
  activeDestination,
  inboxCount,
  items,
}: {
  activeDestination: WorkspaceDestination;
  inboxCount?: number;
  items: NavigationItem[];
}) {
  return (
    <div className={styles.navGroup}>
      {items.map((item) => (
        <NavigationControl
          active={item.destination === activeDestination}
          inboxCount={item.destination === "inbox" ? inboxCount : undefined}
          item={item}
          key={item.destination}
        />
      ))}
    </div>
  );
}

function NavigationControl({
  active,
  inboxCount,
  item,
  mobile = false,
}: {
  active: boolean;
  inboxCount?: number;
  item: NavigationItem;
  mobile?: boolean;
}) {
  const content = (
    <>
      <Icon name={item.icon} size={mobile ? 20 : 18} />
      <span>
        {mobile && item.label === "First Times" ? "Firsts" : item.label}
      </span>
      {!mobile && inboxCount ? <small>{inboxCount}</small> : null}
    </>
  );
  const className = active
    ? mobile
      ? styles.mobileActive
      : styles.activeNavItem
    : undefined;

  if (item.href) {
    return (
      <Link
        aria-current={active ? "page" : undefined}
        className={className}
        href={item.href}
      >
        {content}
      </Link>
    );
  }

  return (
    <button aria-disabled="true" className={className} disabled type="button">
      {content}
    </button>
  );
}

function isNavigationActive(
  item: NavigationItem,
  activeDestination: WorkspaceDestination,
) {
  return (
    item.destination === activeDestination ||
    (item.destination === "library" &&
      ["collections", "first-times", "homes", "trash"].includes(
        activeDestination,
      ))
  );
}

function CaptureControl({
  activeDestination,
  compact = false,
  idPrefix,
  ownerId,
}: {
  activeDestination: WorkspaceDestination;
  compact?: boolean;
  idPrefix: string;
  ownerId: string;
}) {
  if (activeDestination === "home" || activeDestination === "inbox") {
    return (
      <Link
        aria-label={compact ? "New entry" : undefined}
        className={`${styles.captureNavigationLink} ${compact ? styles.compactCaptureNavigationLink : ""}`}
        href="#capture-title"
      >
        <Icon name="plus" size={17} />
        <span>New entry</span>
      </Link>
    );
  }

  return (
    <QuickCaptureDialog
      compact={compact}
      idPrefix={idPrefix}
      ownerId={ownerId}
    />
  );
}
