"use client";

import Link, { useLinkStatus } from "next/link";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import styles from "@/app/page.module.css";
import { AuthGate } from "@/components/auth-gate";
import { BrandMark } from "@/components/brand-mark";
import { Icon, type IconName } from "@/components/icon";
import { QuickCaptureDialog } from "@/components/quick-capture-dialog";
import { SearchShortcutLink } from "@/components/search-shortcut-link";
import { SyncStatus } from "@/components/sync-status";
import { TimezoneSync } from "@/components/timezone-sync";
import type { Viewer } from "@/lib/data/inbox";

export type WorkspaceDestination =
  | "collections"
  | "home"
  | "homes"
  | "inbox"
  | "library"
  | "goals"
  | "places"
  | "people"
  | "search"
  | "settings"
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
  { destination: "goals", href: "/goals", icon: "target", label: "Goals" },
  { destination: "homes", href: "/homes", icon: "home", label: "Homes" },
  { destination: "places", href: "/places", icon: "map", label: "Places" },
  { destination: "people", href: "/people", icon: "archive", label: "People" },
  {
    destination: "vehicles",
    href: "/vehicles",
    icon: "car",
    label: "Vehicles",
  },
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
  {
    destination: "library",
    href: "/library",
    icon: "archive",
    label: "Library",
  },
];

const settingsNavigation: NavigationItem = {
  destination: "settings",
  href: "/settings",
  icon: "settings",
  label: "Settings",
};

export function WorkspaceBoundary({
  children,
  configured,
  inboxCount,
  viewer,
}: {
  children: ReactNode;
  configured: boolean;
  inboxCount?: number;
  viewer: Viewer | null;
}) {
  const pathname = usePathname();

  if (pathname.startsWith("/auth/")) {
    return children;
  }

  if (!viewer) {
    return <AuthGate configured={configured} />;
  }

  return (
    <WorkspaceShell inboxCount={inboxCount} viewer={viewer}>
      {children}
    </WorkspaceShell>
  );
}

export function WorkspaceShell({
  children,
  inboxCount,
  viewer,
}: {
  children: ReactNode;
  inboxCount?: number;
  viewer: Viewer;
}) {
  const activeDestination = destinationForPathname(usePathname());

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
            <BrandMark className={styles.brandMark} />
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
            <Link
              aria-current={
                activeDestination === "settings" ? "page" : undefined
              }
              aria-label={`Open settings for ${viewer.name}`}
              className={styles.avatarButton}
              href="/settings"
            >
              {viewer.initial}
            </Link>
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

function destinationForPathname(pathname: string): WorkspaceDestination {
  if (pathname === "/") return "home";
  if (pathname.startsWith("/search")) return "search";
  if (pathname.startsWith("/settings")) return "settings";
  if (pathname.startsWith("/inbox")) return "inbox";
  if (pathname.startsWith("/timeline")) return "timeline";
  if (pathname.startsWith("/goals")) return "goals";
  if (pathname.startsWith("/homes")) return "homes";
  if (pathname.startsWith("/places")) return "places";
  if (pathname.startsWith("/people")) return "people";
  if (pathname.startsWith("/vehicles")) return "vehicles";
  if (pathname.startsWith("/first-times")) return "first-times";
  if (pathname.startsWith("/collections")) return "collections";
  if (pathname.startsWith("/trash")) return "trash";
  return "library";
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
        <BrandMark className={styles.brandMark} />
        <span>MemoTrail</span>
      </Link>

      <div className={styles.sidebarCaptureButton}>
        <CaptureControl
          activeDestination={activeDestination}
          idPrefix="sidebar-capture"
          ownerId={viewer.id}
        />
      </div>

      <div
        aria-label="Navigation and account"
        className={styles.sidebarScrollRegion}
        role="region"
      >
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
          <nav className={styles.navGroup} aria-label="Settings navigation">
            <NavigationControl
              active={activeDestination === "settings"}
              item={settingsNavigation}
            />
          </nav>
          <div className={styles.archiveNote}>
            <Icon name="clock" size={17} />
            <div>
              <strong>Private cloud sync</strong>
              <span>Available on Web and iPhone</span>
            </div>
          </div>
          <Link
            aria-current={activeDestination === "settings" ? "page" : undefined}
            className={styles.accountLink}
            href="/settings"
            title={`Open settings for ${viewer.email}`}
          >
            <span className={styles.avatar}>{viewer.initial}</span>
            <span>
              <strong>{viewer.name}</strong>
              <small>{viewer.email}</small>
            </span>
            <Icon name="chevron" size={17} />
          </Link>
        </div>
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
        <NavigationPendingIndicator label={item.label} />
      </Link>
    );
  }

  return (
    <button aria-disabled="true" className={className} disabled type="button">
      {content}
    </button>
  );
}

function NavigationPendingIndicator({ label }: { label: string }) {
  const { pending } = useLinkStatus();

  if (!pending) return null;

  return (
    <span
      aria-label={`Opening ${label}`}
      className={styles.navigationProgress}
      role="status"
    />
  );
}

function isNavigationActive(
  item: NavigationItem,
  activeDestination: WorkspaceDestination,
) {
  return (
    item.destination === activeDestination ||
    (item.destination === "library" &&
      [
        "collections",
        "first-times",
        "goals",
        "homes",
        "places",
        "people",
        "trash",
        "vehicles",
      ].includes(activeDestination))
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
