"use client";
import workspaceShellStyles from "@/components/workspace-shell.module.css";

import Link, { useLinkStatus } from "next/link";
import { usePathname } from "next/navigation";
import { useCallback, useState, type ReactNode } from "react";

import { AuthGate } from "@/components/auth-gate";
import { BrandMark } from "@/components/brand-mark";
import { CommandPalette } from "@/components/command-palette";
import { Icon, type IconName } from "@/components/icon";
import { QuickCaptureDialog } from "@/components/quick-capture-dialog";
import { SearchShortcutButton } from "@/components/search-shortcut-link";
import { SyncStatus } from "@/components/sync-status";
import { TimezoneSync } from "@/components/timezone-sync";
import type { Viewer } from "@/lib/data/inbox";
import { SIDEBAR_COOKIE_NAME } from "@/lib/sidebar-preference";

export type WorkspaceDestination =
  | "collections"
  | "home"
  | "homes"
  | "inbox"
  | "library"
  | "map"
  | "goals"
  | "people"
  | "settings"
  | "tags"
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
  { destination: "home", href: "/", icon: "dashboard", label: "Home" },
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
  { destination: "map", href: "/map", icon: "map", label: "Map" },
];

const recordNavigation: NavigationItem[] = [
  { destination: "people", href: "/people", icon: "person", label: "People" },
  { destination: "homes", href: "/homes", icon: "home", label: "Homes" },
  {
    destination: "vehicles",
    href: "/vehicles",
    icon: "car",
    label: "Vehicles",
  },
  {
    destination: "first-times",
    href: "/first-times",
    icon: "star",
    label: "First Times",
  },
  { destination: "goals", href: "/goals", icon: "target", label: "Goals" },
];

const organizationNavigation: NavigationItem[] = [
  {
    destination: "collections",
    href: "/collections",
    icon: "archive",
    label: "Collections",
  },
  { destination: "tags", href: "/tags", icon: "tag", label: "Tags" },
  { destination: "trash", href: "/trash", icon: "trash", label: "Trash" },
];

const mobileNavigation: NavigationItem[] = [
  { destination: "home", href: "/", icon: "dashboard", label: "Home" },
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
  initialSidebarCollapsed,
  viewer,
}: {
  children: ReactNode;
  configured: boolean;
  inboxCount?: number;
  initialSidebarCollapsed: boolean;
  viewer: Viewer | null;
}) {
  const pathname = usePathname();

  if (pathname.startsWith("/auth/")) {
    return children;
  }

  if (pathname === "/design-system" && process.env.NODE_ENV !== "production") {
    return children;
  }

  if (!viewer) {
    return <AuthGate configured={configured} />;
  }

  return (
    <WorkspaceShell
      inboxCount={inboxCount}
      initialSidebarCollapsed={initialSidebarCollapsed}
      viewer={viewer}
    >
      {children}
    </WorkspaceShell>
  );
}

export function WorkspaceShell({
  children,
  inboxCount,
  initialSidebarCollapsed,
  viewer,
}: {
  children: ReactNode;
  inboxCount?: number;
  initialSidebarCollapsed: boolean;
  viewer: Viewer;
}) {
  const pathname = usePathname();
  const activeDestination = destinationForPathname(pathname);
  const [commandPaletteOpen, setCommandPaletteOpen] = useState(false);
  const [quickCaptureOpen, setQuickCaptureOpen] = useState(false);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(
    initialSidebarCollapsed,
  );
  const closeCommandPalette = useCallback(
    () => setCommandPaletteOpen(false),
    [],
  );
  const closeQuickCapture = useCallback(() => setQuickCaptureOpen(false), []);
  const openCommandPalette = useCallback(() => {
    setQuickCaptureOpen(false);
    setCommandPaletteOpen(true);
  }, []);
  const openQuickCapture = useCallback(() => {
    setCommandPaletteOpen(false);
    setQuickCaptureOpen(true);
  }, []);

  function toggleSidebar() {
    const next = !sidebarCollapsed;
    setSidebarCollapsed(next);
    document.cookie = `${SIDEBAR_COOKIE_NAME}=${next ? "collapsed" : "expanded"}; Path=/; Max-Age=31536000; SameSite=Lax`;
  }

  return (
    <div
      className={workspaceShellStyles.appShell}
      data-sidebar-collapsed={sidebarCollapsed}
    >
      <TimezoneSync />
      <CommandPalette onClose={closeCommandPalette} open={commandPaletteOpen} />
      <Sidebar
        activeDestination={activeDestination}
        collapsed={sidebarCollapsed}
        inboxCount={inboxCount}
        onToggle={toggleSidebar}
      />

      <main className={workspaceShellStyles.workspace}>
        <header className={workspaceShellStyles.topBar}>
          <div className={workspaceShellStyles.topLeading}>
            <Link
              className={workspaceShellStyles.mobileBrand}
              href="/"
              aria-label="MemoTrail home"
            >
              <BrandMark className={workspaceShellStyles.brandMark} />
              <span>MemoTrail</span>
            </Link>
            <QuickCaptureDialog
              idPrefix="topbar-capture"
              onClose={closeQuickCapture}
              onOpen={openQuickCapture}
              open={quickCaptureOpen}
              ownerId={viewer.id}
              triggerClassName={`${workspaceShellStyles.topActionButton} ${workspaceShellStyles.newEntryTopAction}`}
            />
          </div>

          <div className={workspaceShellStyles.topActions}>
            <SyncStatus ownerId={viewer.id} />
            <SearchShortcutButton
              className={workspaceShellStyles.topActionButton}
              onOpen={openCommandPalette}
            />
            <Link
              aria-current={activeDestination === "inbox" ? "page" : undefined}
              aria-label={
                inboxCount
                  ? `Open Inbox, ${inboxCount} ${inboxCount === 1 ? "item" : "items"}`
                  : "Open Inbox"
              }
              className={`${workspaceShellStyles.topActionButton} ${workspaceShellStyles.inboxTopAction}`}
              href="/inbox"
            >
              <Icon name="inbox" size={18} />
              {inboxCount ? (
                <small aria-hidden="true">{inboxCount}</small>
              ) : null}
              <NavigationPendingIndicator label="Inbox" />
            </Link>
            <Link
              aria-current={activeDestination === "trash" ? "page" : undefined}
              aria-label="Open Trash"
              className={workspaceShellStyles.mobileTrashButton}
              href="/trash"
            >
              <Icon name="trash" size={19} />
            </Link>
            <Link
              aria-current={
                activeDestination === "settings" ? "page" : undefined
              }
              aria-label={`Open settings for ${viewer.name}`}
              className={workspaceShellStyles.avatarButton}
              href="/settings"
            >
              {viewer.initial}
            </Link>
          </div>
        </header>

        {children}
      </main>

      <nav
        className={workspaceShellStyles.mobileNavigation}
        aria-label="Mobile navigation"
      >
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
  if (pathname.startsWith("/search")) return "library";
  if (pathname.startsWith("/settings")) return "settings";
  if (pathname.startsWith("/inbox")) return "inbox";
  if (pathname.startsWith("/timeline")) return "timeline";
  if (pathname.startsWith("/goals")) return "goals";
  if (pathname.startsWith("/homes")) return "homes";
  if (pathname.startsWith("/map")) return "map";
  if (pathname.startsWith("/people")) return "people";
  if (pathname.startsWith("/vehicles")) return "vehicles";
  if (pathname.startsWith("/first-times")) return "first-times";
  if (pathname.startsWith("/collections")) return "collections";
  if (pathname.startsWith("/tags")) return "tags";
  if (pathname.startsWith("/trash")) return "trash";
  return "library";
}

function Sidebar({
  activeDestination,
  collapsed,
  inboxCount,
  onToggle,
}: {
  activeDestination: WorkspaceDestination;
  collapsed: boolean;
  inboxCount?: number;
  onToggle: () => void;
}) {
  return (
    <aside className={workspaceShellStyles.sidebar}>
      <div className={workspaceShellStyles.sidebarHeader}>
        <Link
          aria-hidden={collapsed}
          className={workspaceShellStyles.brand}
          href="/"
          tabIndex={collapsed ? -1 : undefined}
        >
          <BrandMark className={workspaceShellStyles.brandMark} />
          <span className={workspaceShellStyles.brandName}>MemoTrail</span>
        </Link>
        <button
          aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
          className={workspaceShellStyles.sidebarToggle}
          onClick={onToggle}
          title={collapsed ? "Expand sidebar" : "Collapse sidebar"}
          type="button"
        >
          <Icon name={collapsed ? "sidebarClosed" : "sidebarOpen"} size={18} />
        </button>
      </div>

      <div
        aria-label="Sidebar navigation"
        className={workspaceShellStyles.sidebarScrollRegion}
        role="region"
      >
        <nav aria-label="Primary navigation">
          <NavGroup
            activeDestination={activeDestination}
            collapsed={collapsed}
            inboxCount={inboxCount}
            items={primaryNavigation}
          />
          <div className={workspaceShellStyles.navDivider} role="separator" />
          <p aria-hidden={collapsed} className={workspaceShellStyles.navLabel}>
            Focused views
          </p>
          <NavGroup
            activeDestination={activeDestination}
            collapsed={collapsed}
            items={recordNavigation}
          />
          <div className={workspaceShellStyles.navDivider} role="separator" />
          <p aria-hidden={collapsed} className={workspaceShellStyles.navLabel}>
            Organize
          </p>
          <NavGroup
            activeDestination={activeDestination}
            collapsed={collapsed}
            items={organizationNavigation}
          />
        </nav>

        <div className={workspaceShellStyles.sidebarFooter}>
          <div className={workspaceShellStyles.navDivider} role="separator" />
          <nav
            className={workspaceShellStyles.navGroup}
            aria-label="Settings navigation"
          >
            <NavigationControl
              active={activeDestination === "settings"}
              collapsed={collapsed}
              item={settingsNavigation}
            />
          </nav>
        </div>
      </div>
    </aside>
  );
}

function NavGroup({
  activeDestination,
  collapsed,
  inboxCount,
  items,
}: {
  activeDestination: WorkspaceDestination;
  collapsed: boolean;
  inboxCount?: number;
  items: NavigationItem[];
}) {
  return (
    <div className={workspaceShellStyles.navGroup}>
      {items.map((item) => (
        <NavigationControl
          active={item.destination === activeDestination}
          collapsed={collapsed}
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
  collapsed = false,
  inboxCount,
  item,
  mobile = false,
}: {
  active: boolean;
  collapsed?: boolean;
  inboxCount?: number;
  item: NavigationItem;
  mobile?: boolean;
}) {
  const content = (
    <>
      <Icon name={item.icon} size={mobile ? 20 : 18} />
      <span className={workspaceShellStyles.navItemLabel}>
        {mobile && item.label === "First Times" ? "Firsts" : item.label}
      </span>
      {!mobile && inboxCount ? <small>{inboxCount}</small> : null}
    </>
  );
  const className = active
    ? mobile
      ? workspaceShellStyles.mobileActive
      : workspaceShellStyles.activeNavItem
    : undefined;

  if (item.href) {
    return (
      <Link
        aria-current={active ? "page" : undefined}
        aria-label={collapsed ? item.label : undefined}
        className={className}
        href={item.href}
        title={collapsed ? item.label : undefined}
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
      className={workspaceShellStyles.navigationProgress}
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
        "people",
        "tags",
        "trash",
        "vehicles",
      ].includes(activeDestination))
  );
}
