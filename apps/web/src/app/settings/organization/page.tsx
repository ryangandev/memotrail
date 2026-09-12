import Link from "next/link";
import { AuthGate } from "@/components/auth-gate";
import { WorkspaceShell } from "@/components/workspace-shell";
import { OrganizationSettings } from "@/components/organization-settings";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { getSupabasePublicConfig } from "@/lib/supabase/config";
import type { OrganizationItem } from "@/lib/data/organization";
import styles from "./page.module.css";
export const dynamic = "force-dynamic";
export default async function OrganizationPage({
  searchParams,
}: {
  searchParams: Promise<{ kind?: string; q?: string; page?: string }>;
}) {
  if (!getSupabasePublicConfig()) return <AuthGate configured={false} />;
  const context = await getAuthenticatedContext();
  if (!context) return <AuthGate configured />;
  const params = await searchParams;
  const kind = params.kind === "tag" ? "tag" : "collection";
  const query = (params.q ?? "").trim().slice(0, 200);
  const rawPage = Number(params.page ?? 1);
  const page =
    Number.isSafeInteger(rawPage) && rawPage > 0 && rawPage <= 1000000
      ? rawPage
      : 1;
  const result = await context.client.rpc("organization_workspace", {
    p_kind: kind,
    p_query: query,
    p_limit: 50,
    p_offset: (page - 1) * 50,
  });
  const items = (result.data ?? []) as OrganizationItem[];
  return (
    <WorkspaceShell activeDestination="collections" viewer={context.viewer}>
      <div className={styles.workspace}>
        <header>
          <Link href="/collections">Back to Collections</Link>
          <p className={styles.eyebrow}>A PLACE FOR EVERY THREAD</p>
          <h1>Organize your archive</h1>
          <p>
            Shape the Collections and tags that connect your Entries. Names
            change everywhere, without duplicating your writing.
          </p>
        </header>
        <nav className={styles.tabs} aria-label="Organization kind">
          <Link
            aria-current={kind === "collection" ? "page" : undefined}
            href="/settings/organization"
          >
            Collections
          </Link>
          <Link
            aria-current={kind === "tag" ? "page" : undefined}
            href="/settings/organization?kind=tag"
          >
            Tags
          </Link>
        </nav>
        <form className={styles.search}>
          <input type="hidden" name="kind" value={kind} />
          <label htmlFor="organization-search">
            Find {kind === "tag" ? "tags" : "Collections"}
          </label>
          <div>
            <input
              id="organization-search"
              name="q"
              defaultValue={query}
              maxLength={200}
              placeholder="Search names"
            />
            <button>Search names</button>
          </div>
        </form>
        {result.error ? (
          <p role="alert">
            Could not load organization settings. Refresh to try again.
          </p>
        ) : (
          <OrganizationSettings
            key={`${kind}:${query}:${page}`}
            items={items}
            kind={kind}
          />
        )}
        <nav className={styles.pagination} aria-label="Organization pages">
          {page > 1 && (
            <Link
              href={`?kind=${kind}&q=${encodeURIComponent(query)}&page=${page - 1}`}
            >
              Previous items
            </Link>
          )}
          <span>Page {page}</span>
          {(items[0]?.total_count ?? 0) > page * 50 && (
            <Link
              href={`?kind=${kind}&q=${encodeURIComponent(query)}&page=${page + 1}`}
            >
              More items
            </Link>
          )}
        </nav>
        <p className={styles.hint}>
          Removed Collections can be recovered in{" "}
          <Link href="/trash">Trash</Link>. Tags can be removed from individual
          Entries in review.
        </p>
      </div>
    </WorkspaceShell>
  );
}
