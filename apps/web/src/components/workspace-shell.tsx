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
import { Icon } from "@/components/icon";
import { QuickCaptureDialog } from "@/components/quick-capture-dialog";
import { SyncStatus } from "@/components/sync-status";
import { TimezoneSync } from "@/components/timezone-sync";
import { WorkspaceActionDock } from "@/components/workspace-action-dock";
import { DeclareDestinationContext } from "@/components/workspace-destination";
import type { Viewer } from "@/lib/data/inbox";
import { SIDEBAR_COOKIE_NAME } from "@/lib/sidebar-preference";
import {
  destinationForPathname,
  moreDestinations,
  sidebarGroups,
  tabBarDestinations,
  type DestinationLink,
  type WorkspaceDestination,
} from "@/lib/workspace-destinations";

const [dailyDestinations, focusedDestinations, toolDestinations] =
  sidebarGroups;

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
  // A page whose address cannot say where it belongs, such as an Item, declares it.
  const [declaredDestination, setDeclaredDestination] =
    useState<WorkspaceDestination | null>(null);
  const activeDestination =
    declaredDestination ?? destinationForPathname(pathname);
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
  const closeMobileMore = useCallback(() => setMobileMoreOpen(false), []);

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

  const moreActive =
    activeDestination !== null &&
    !tabBarDestinations.some((item) => item.destination === activeDestination);

  return (
    <DeclareDestinationContext.Provider value={setDeclaredDestination}>
      <div
        className={workspaceShellStyles.appShell}
        data-sidebar-collapsed={sidebarCollapsed}
      >
        <TimezoneSync />
        <CommandPalette
          onClose={closeCommandPalette}
          onNewEntry={openQuickCapture}
          open={commandPaletteOpen}
        />
        <Sidebar
          activeDestination={activeDestination}
          collapsed={sidebarCollapsed}
          onToggle={toggleSidebar}
          viewer={viewer}
        />

        <main className={workspaceShellStyles.workspace}>
          {/* The phone's top bar; on wider screens the sidebar holds all of this. */}
          <header className={workspaceShellStyles.topBar}>
            <Link
              aria-label="MemoTrail dashboard"
              className={workspaceShellStyles.mobileBrand}
              href="/"
            >
              <BrandMark className={workspaceShellStyles.brandMark} />
              <span>MemoTrail</span>
            </Link>
            <div className={workspaceShellStyles.topActions}>
              <SyncStatus idleLabel="Synced" />
              <Link
                aria-current={
                  activeDestination === "settings" ? "page" : undefined
                }
                aria-label={`Open settings for ${viewer.name}`}
                className={workspaceShellStyles.avatar}
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
          aria-label="Mobile navigation"
          className={workspaceShellStyles.mobileNavigation}
        >
          {tabBarDestinations.map((item) => (
            <NavigationControl
              active={item.destination === activeDestination}
              item={item}
              key={item.destination}
              mobile
              onNavigate={closeMobileMore}
            />
          ))}
          <button
            aria-controls={mobileMoreOpen ? "mobile-more-menu" : undefined}
            aria-expanded={mobileMoreOpen}
            aria-label="More destinations"
            className={
              moreActive ? workspaceShellStyles.mobileActive : undefined
            }
            onClick={() => setMobileMoreOpen((open) => !open)}
            ref={mobileMoreButton}
            type="button"
          >
            <Icon name="more" size={22} />
            <span>More</span>
          </button>
        </nav>
        {mobileMoreOpen ? (
          <>
            <button
              aria-label="Close more destinations"
              className={workspaceShellStyles.mobileMoreScrim}
              onClick={closeMobileMore}
              tabIndex={-1}
              type="button"
            />
            <nav
              aria-label="More destinations"
              className={workspaceShellStyles.mobileMoreMenu}
              id="mobile-more-menu"
            >
              <ul className={workspaceShellStyles.mobileMoreList}>
                {moreDestinations.map((item) => (
                  <li key={item.destination}>
                    <Link
                      aria-current={
                        item.destination === activeDestination
                          ? "page"
                          : undefined
                      }
                      href={item.href}
                      onClick={closeMobileMore}
                    >
                      {item.label}
                    </Link>
                  </li>
                ))}
              </ul>
            </nav>
          </>
        ) : null}
      </div>
    </DeclareDestinationContext.Provider>
  );
}

function Sidebar({
  activeDestination,
  collapsed,
  onToggle,
  viewer,
}: {
  activeDestination: WorkspaceDestination | null;
  collapsed: boolean;
  onToggle: () => void;
  viewer: Viewer;
}) {
  const toggleLabel = collapsed ? "Expand sidebar" : "Collapse sidebar";
  return (
    <aside className={workspaceShellStyles.sidebar}>
      <div className={workspaceShellStyles.sidebarHeader}>
        {/* Collapsed, the logo is the toggle's resting face, so only the toggle is reachable. */}
        <Link
          aria-hidden={collapsed || undefined}
          aria-label="MemoTrail dashboard"
          className={workspaceShellStyles.brand}
          href="/"
          tabIndex={collapsed ? -1 : undefined}
        >
          <BrandMark
            className={workspaceShellStyles.brandMark}
            collapsed={collapsed}
            motion="counter-rotation"
          />
          <span className={workspaceShellStyles.brandName}>MemoTrail</span>
        </Link>
        <button
          aria-keyshortcuts="Meta+B Control+B"
          aria-label={toggleLabel}
          className={workspaceShellStyles.sidebarToggle}
          onClick={onToggle}
          title={`${toggleLabel} (⌘ B / Ctrl+B)`}
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
            items={dailyDestinations}
          />
          <div className={workspaceShellStyles.navDivider} role="separator" />
          <NavGroup
            activeDestination={activeDestination}
            collapsed={collapsed}
            items={focusedDestinations}
          />
        </nav>

        <div className={workspaceShellStyles.sidebarFooter}>
          <nav aria-label="Workspace tools">
            <NavGroup
              activeDestination={activeDestination}
              collapsed={collapsed}
              items={toolDestinations}
            />
          </nav>
          <div className={workspaceShellStyles.account}>
            <span
              aria-hidden="true"
              className={workspaceShellStyles.avatar}
              title={collapsed ? viewer.name : undefined}
            >
              {viewer.initial}
            </span>
            <span className={workspaceShellStyles.accountName}>
              {viewer.name}
            </span>
            <SyncStatus idleLabel="Synced" />
          </div>
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
  activeDestination: WorkspaceDestination | null;
  collapsed: boolean;
  items: readonly DestinationLink[];
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
  item: DestinationLink;
  mobile?: boolean;
  onNavigate?: () => void;
}) {
  const className = active
    ? mobile
      ? workspaceShellStyles.mobileActive
      : workspaceShellStyles.activeNavItem
    : undefined;

  return (
    <Link
      aria-current={active ? "page" : undefined}
      aria-label={collapsed ? item.label : undefined}
      className={className}
      href={item.href}
      onClick={onNavigate}
      title={collapsed ? item.label : undefined}
    >
      <Icon name={item.icon} size={mobile ? 22 : 18} />
      <span className={workspaceShellStyles.navItemLabel}>{item.label}</span>
      <NavigationPendingIndicator label={item.label} />
    </Link>
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
