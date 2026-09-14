import type { Metadata } from "next";
import type { ReactNode } from "react";
import { WorkspaceBoundary } from "@/components/workspace-shell";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { getSupabasePublicConfig } from "@/lib/supabase/config";
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
  const context = configured ? await getAuthenticatedContext() : null;
  const inbox = context
    ? await context.client
        .from("entries")
        .select("id", { count: "exact", head: true })
        .eq("owner_id", context.userId)
        .eq("inbox_status", "unreviewed")
        .is("deleted_at", null)
    : null;

  return (
    <html lang="en">
      <body>
        <WorkspaceBoundary
          configured={configured}
          inboxCount={inbox?.error ? undefined : inbox?.count ?? undefined}
          viewer={context?.viewer ?? null}
        >
          {children}
        </WorkspaceBoundary>
      </body>
    </html>
  );
}
