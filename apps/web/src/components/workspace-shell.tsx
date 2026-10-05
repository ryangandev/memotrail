"use client";
import workspaceShellStyles from "@/components/workspace-shell.module.css";

import Link, { useLinkStatus } from "next/link";
import { usePathname } from "next/navigation";
import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";

import { AuthGate } from "@/components/auth-gate";
import { BrandMark } from "@/components/brand-mark";
import { CaptureProvider } from "@/components/capture-provider";
import { CommandPalette } from "@/components/command-palette";
import { Icon, type IconName } from "@/components/icon";
import { QuickCaptureDialog } from "@/components/quick-capture-dialog";
import { SyncStatus } from "@/components/sync-status";
import { TimezoneSync } from "@/components/timezone-sync";
import { WorkspaceHistoryControls } from "@/components/workspace-history-controls";
import { WorkspaceActionDock } from "@/components/workspace-action-dock";
import type { Viewer } from "@/lib/data/inbox";
import { SIDEBAR_COOKIE_NAME } from "@/lib/sidebar-preference";

export type WorkspaceDestination =
  | "explore"
  | "home"
  | "homes"
  | "library"
  | "map"
  | "goals"
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

const mapNavigation: NavigationItem = {
  destination: "map",
  href: "/map",
  icon: "map",
  label: "Map",
};

const primaryNavigation: NavigationItem[] = [
  { destination: "home", href: "/", icon: "dashboard", label: "Dashboard" },
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
  mapNavigation,
];

const recordNavigation: NavigationItem[] = [
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
  { destination: "goals", href: "/goals", icon: "target", label: "Someday" },
];

const organizationNavigation: NavigationItem[] = [
  { destination: "tags", href: "/tags", icon: "tag", label: "Tags" },
  { destination: "trash", href: "/trash", icon: "trash", label: "Trash" },
];

const mobileNavigation: NavigationItem[] = [
  { destination: "home", href: "/", icon: "dashboard", label: "Dashboard" },
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
  mapNavigation,
];

const mobileMoreGroups: { label: string; items: NavigationItem[] }[] = [
  { label: "Focused views", items: recordNavigation },
  { label: "Organize", items: organizationNavigation.slice(0, 1) },
  {
    label: "Trash and settings",
    items: [
      organizationNavigation[1],
      {
        destination: "settings",
        href: "/settings",
        icon: "settings",
        label: "Settings",
      },
    ],
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
  initialSidebarCollapsed,
  viewer,
}: {
  children: ReactNode;
  configured: boolean;
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
    <CaptureProvider ownerId={viewer.id}>
      <WorkspaceShell
        initialSidebarCollapsed={initialSidebarCollapsed}
        viewer={viewer}
      >
        {children}
      </WorkspaceShell>
    </CaptureProvider>
  );
}

export function WorkspaceShell({
  children,
  initialSidebarCollapsed,
  viewer,
}: {
  children: ReactNode;
  initialSidebarCollapsed: boolean;
  viewer: Viewer;
}) {
  const pathname = usePathname();
  const activeDestination = destinationForPathname(pathname);
  const [commandPaletteOpen, setCommandPaletteOpen] = useState(false);
  const [quickCaptureOpen, setQuickCaptureOpen] = useState(false);
  const [mobileMoreOpen, setMobileMoreOpen] = useState(false);
  const mobileMoreButton = useRef<HTMLButtonElement>(null);
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
    setMobileMoreOpen(false);
    setQuickCaptureOpen(true);
  }, []);

  useEffect(() => {
    if (!mobileMoreOpen) return;
    function closeOnEscape(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setMobileMoreOpen(false);
        mobileMoreButton.current?.focus();
      }
    }
    document.addEventListener("keydown", closeOnEscape);
    return () => document.removeEventListener("keydown", closeOnEscape);
  }, [mobileMoreOpen]);

  const toggleSidebar = useCallback(() => {
    const next = !sidebarCollapsed;
    setSidebarCollapsed(next);
    document.cookie = `${SIDEBAR_COOKIE_NAME}=${next ? "collapsed" : "expanded"}; Path=/; Max-Age=31536000; SameSite=Lax`;
  }, [sidebarCollapsed]);

  useEffect(() => {
    function handleSidebarShortcut(event: KeyboardEvent) {
      if (
        event.defaultPrevented ||
        event.key.toLowerCase() !== "b" ||
        (!event.metaKey && !event.ctrlKey) ||
        event.altKey ||
        event.shiftKey ||
        event.repeat ||
        event.isComposing ||
        !window.matchMedia("(min-width: 721px)").matches ||
        (event.target instanceof HTMLElement &&
          (event.target.isContentEditable ||
            event.target.closest(
              "input, textarea, select, [data-rich-text-editor]",
            )))
      ) {
        return;
      }
      event.preventDefault();
      toggleSidebar();
    }
    window.addEventListener("keydown", handleSidebarShortcut);
    return () => window.removeEventListener("keydown", handleSidebarShortcut);
  }, [toggleSidebar]);

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
      />

      <main className={workspaceShellStyles.workspace}>
        <header className={workspaceShellStyles.topBar}>
          <div className={workspaceShellStyles.topLeading}>
            <Link
              className={workspaceShellStyles.mobileBrand}
              href="/"
              aria-label="MemoTrail dashboard"
            >
              <BrandMark className={workspaceShellStyles.brandMark} />
              <span>MemoTrail</span>
            </Link>
            <WorkspaceHistoryControls />
            <button
              aria-keyshortcuts="Meta+B Control+B"
              aria-label={
                sidebarCollapsed ? "Expand sidebar" : "Collapse sidebar"
              }
              className={workspaceShellStyles.sidebarToggle}
              onClick={toggleSidebar}
              title={`${sidebarCollapsed ? "Expand sidebar" : "Collapse sidebar"} (⌘ B / Ctrl+B)`}
              type="button"
            >
              <Icon
                name={sidebarCollapsed ? "sidebarClosed" : "sidebarOpen"}
                size={18}
              />
            </button>
          </div>

          <div className={workspaceShellStyles.topActions}>
            <SyncStatus />
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

      <WorkspaceActionDock onSearch={openCommandPalette}>
        <QuickCaptureDialog
          idPrefix="dock-capture"
          onClose={closeQuickCapture}
          onOpen={openQuickCapture}
          open={quickCaptureOpen}
        />
      </WorkspaceActionDock>

      <nav
        className={workspaceShellStyles.mobileNavigation}
        aria-label="Mobile navigation"
      >
        {mobileNavigation.map((item) => (
          <NavigationControl
            active={item.destination === activeDestination}
            item={item}
            key={item.destination}
            mobile
            onNavigate={() => setMobileMoreOpen(false)}
          />
        ))}
        <button
          aria-controls={mobileMoreOpen ? "mobile-more-menu" : undefined}
          aria-expanded={mobileMoreOpen}
          aria-label="More destinations"
          className={
            !mobileNavigation.some(
              (item) => item.destination === activeDestination,
            )
              ? workspaceShellStyles.mobileActive
              : undefined
          }
          onClick={() => setMobileMoreOpen((open) => !open)}
          ref={mobileMoreButton}
          type="button"
        >
          <Icon name="more" size={20} />
          <span>More</span>
        </button>
      </nav>
      {mobileMoreOpen ? (
        <>
          <button
            aria-label="Close more destinations"
            className={workspaceShellStyles.mobileMoreScrim}
            onClick={() => setMobileMoreOpen(false)}
            tabIndex={-1}
            type="button"
          />
          <nav
            aria-label="More destinations"
            className={workspaceShellStyles.mobileMoreMenu}
            id="mobile-more-menu"
          >
            <div className={workspaceShellStyles.mobileMoreHeader}>
              <h2>More</h2>
              <button
                aria-label="Close more destinations"
                onClick={() => setMobileMoreOpen(false)}
                type="button"
              >
                <Icon name="close" size={18} />
              </button>
            </div>
            {mobileMoreGroups.map((group) => (
              <div
                className={workspaceShellStyles.mobileMoreGroup}
                key={group.label}
              >
                <h3>{group.label}</h3>
                <div className={workspaceShellStyles.mobileMoreLinks}>
                  {group.items.map((item) => (
                    <Link
                      aria-current={
                        item.destination === activeDestination
                          ? "page"
                          : undefined
                      }
                      href={item.href ?? "/"}
                      key={item.href}
                      onClick={() => setMobileMoreOpen(false)}
                    >
                      <Icon name={item.icon} size={18} />
                      <span>{item.label}</span>
                    </Link>
                  ))}
                </div>
              </div>
            ))}
          </nav>
        </>
      ) : null}
    </div>
  );
}

function destinationForPathname(pathname: string): WorkspaceDestination {
  if (pathname === "/") return "home";
  if (pathname.startsWith("/explore")) return "explore";
  if (pathname.startsWith("/settings")) return "settings";
  if (pathname.startsWith("/timeline")) return "timeline";
  if (pathname.startsWith("/goals")) return "goals";
  if (pathname.startsWith("/homes")) return "homes";
  if (pathname.startsWith("/map")) return "map";
  if (pathname.startsWith("/vehicles")) return "vehicles";
  if (pathname.startsWith("/first-times")) return "first-times";
  if (pathname.startsWith("/tags")) return "tags";
  if (pathname.startsWith("/trash")) return "trash";
  return "library";
}

function Sidebar({
  activeDestination,
  collapsed,
}: {
  activeDestination: WorkspaceDestination;
  collapsed: boolean;
}) {
  return (
    <aside className={workspaceShellStyles.sidebar}>
      <div className={workspaceShellStyles.sidebarHeader}>
        <Link
          aria-label="MemoTrail dashboard"
          className={workspaceShellStyles.brand}
          href="/"
        >
          <BrandMark
            className={workspaceShellStyles.brandMark}
            collapsed={collapsed}
            motion="counter-rotation"
          />
          <span className={workspaceShellStyles.brandName}>MemoTrail</span>
        </Link>
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
  items,
}: {
  activeDestination: WorkspaceDestination;
  collapsed: boolean;
  items: NavigationItem[];
}) {
  return (
    <div className={workspaceShellStyles.navGroup}>
      {items.map((item) => (
        <NavigationControl
          active={item.destination === activeDestination}
          collapsed={collapsed}
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
  item,
  mobile = false,
  onNavigate,
}: {
  active: boolean;
  collapsed?: boolean;
  item: NavigationItem;
  mobile?: boolean;
  onNavigate?: () => void;
}) {
  const content = (
    <>
      <Icon name={item.icon} size={mobile ? 20 : 18} />
      <span className={workspaceShellStyles.navItemLabel}>
        {mobile && item.label === "First Times" ? "Firsts" : item.label}
      </span>
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
        onClick={onNavigate}
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
