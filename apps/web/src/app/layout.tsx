import type { Metadata } from "next";
import { cookies } from "next/headers";
import type { ReactNode } from "react";
import { ConfirmationDialogProvider } from "@/components/confirmation-dialog";
import { AppToaster } from "@/components/app-toast";
import { WorkspaceBoundary } from "@/components/workspace-shell";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { getSupabasePublicConfig } from "@/lib/supabase/config";
import {
  SIDEBAR_COOKIE_NAME,
  sidebarIsCollapsed,
} from "@/lib/sidebar-preference";
import {
  explicitTheme,
  storedThemePreference,
  THEME_COOKIE_NAME,
} from "@/lib/theme";
import "./globals.css";

export const metadata: Metadata = {
  title: "MemoTrail",
  description: "A private record of a life in progress.",
};

type RootLayoutProps = Readonly<{
  children: ReactNode;
}>;

export default async function RootLayout({ children }: RootLayoutProps) {
  const configured = Boolean(getSupabasePublicConfig());
  const [context, cookieStore] = await Promise.all([
    configured ? getAuthenticatedContext() : Promise.resolve(null),
    cookies(),
  ]);
  const theme = explicitTheme(
    storedThemePreference(cookieStore.get(THEME_COOKIE_NAME)?.value),
  );

  return (
    <html data-theme={theme} lang="en">
      <body>
        <ConfirmationDialogProvider>
          <WorkspaceBoundary
            configured={configured}
            initialSidebarCollapsed={sidebarIsCollapsed(
              cookieStore.get(SIDEBAR_COOKIE_NAME)?.value,
            )}
            viewer={context?.viewer ?? null}
          >
            {children}
          </WorkspaceBoundary>
        </ConfirmationDialogProvider>
        <AppToaster />
      </body>
    </html>
  );
}
