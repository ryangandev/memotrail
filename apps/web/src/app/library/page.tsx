import Link from "next/link";
import { AuthGate } from "@/components/auth-gate";
import { Icon } from "@/components/icon";
import { WorkspaceShell } from "@/components/workspace-shell";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { getSupabasePublicConfig } from "@/lib/supabase/config";
import styles from "./page.module.css";

export const dynamic = "force-dynamic";

const availableDestinations = [
  {
    detail: "Browse the themes that connect your Entries.",
    href: "/collections",
    icon: "archive" as const,
    title: "Collections",
  },
  {
    detail: "Revisit the experiences you tried, saw, or learned first.",
    href: "/first-times",
    icon: "star" as const,
    title: "First Times",
  },
  {
    detail:
      "Revisit the locations connected to your Entries and Home chapters.",
    href: "/places",
    icon: "map" as const,
    title: "Places",
  },
  {
    detail: "Restore removed items or permanently clear them.",
    href: "/trash",
    icon: "trash" as const,
    title: "Trash",
  },
  {
    detail: "Revisit every place you called home and the chapter around it.",
    href: "/homes",
    icon: "home" as const,
    title: "Homes",
  },
  {
    detail: "Remember every vehicle and the chapter it carried you through.",
    href: "/vehicles",
    icon: "car" as const,
    title: "Vehicles",
  },
  {
    detail: "Keep active plans, distant hopes, and someday ideas close.",
    href: "/goals",
    icon: "target" as const,
    title: "Goals",
  },
];

const plannedDestinations = ["People"];

export default async function LibraryPage() {
  if (!getSupabasePublicConfig()) {
    return <AuthGate configured={false} />;
  }

  const context = await getAuthenticatedContext();

  if (!context) {
    return <AuthGate configured />;
  }

  const inbox = await context.client
    .from("entries")
    .select("id", { count: "exact", head: true })
    .eq("owner_id", context.userId)
    .eq("inbox_status", "unreviewed")
    .is("deleted_at", null);

  return (
    <WorkspaceShell
      activeDestination="library"
      inboxCount={inbox.error ? undefined : (inbox.count ?? 0)}
      viewer={context.viewer}
    >
      <div className={styles.content}>
        <header className={styles.header}>
          <p>Your personal archive</p>
          <h1>Library</h1>
          <span>
            Open a part of your life without duplicating the Entries behind it.
          </span>
        </header>

        <section aria-labelledby="available-library-heading">
          <div className={styles.sectionHeading}>
            <h2 id="available-library-heading">Available now</h2>
            <span>Seven ways into the archive</span>
          </div>
          <div className={styles.availableGrid}>
            {availableDestinations.map((destination) => (
              <Link href={destination.href} key={destination.href}>
                <span>
                  <Icon name={destination.icon} size={20} />
                </span>
                <div>
                  <strong>{destination.title}</strong>
                  <p>{destination.detail}</p>
                </div>
                <Icon name="chevron" size={15} />
              </Link>
            ))}
          </div>
        </section>

        <section aria-labelledby="planned-library-heading">
          <div className={styles.sectionHeading}>
            <h2 id="planned-library-heading">Planned archives</h2>
            <span>Built from the same Entry model</span>
          </div>
          <div className={styles.plannedGrid}>
            {plannedDestinations.map((destination) => (
              <article key={destination}>
                <span>{destination}</span>
                <small>Planned</small>
              </article>
            ))}
          </div>
        </section>
      </div>
    </WorkspaceShell>
  );
}
