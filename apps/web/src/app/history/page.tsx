import Link from "next/link";
import { AuthGate } from "@/components/auth-gate";
import { WorkspaceShell } from "@/components/workspace-shell";
import { EntryHistoryView } from "@/components/entry-history-view";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { getSupabasePublicConfig } from "@/lib/supabase/config";
import {
  historyTitle,
  historyPage,
  validHistoryID,
  type EntryHistory,
  type HistoryIndexEntry,
} from "@/lib/data/history";
import styles from "./page.module.css";
export const dynamic = "force-dynamic";
export default async function HistoryPage({
  searchParams,
}: {
  searchParams: Promise<{ entry?: string; page?: string; q?: string }>;
}) {
  if (!getSupabasePublicConfig()) return <AuthGate configured={false} />;
  const context = await getAuthenticatedContext();
  if (!context) return <AuthGate configured />;
  const params = await searchParams;
  const selected = validHistoryID(params.entry) ? params.entry : null;
  const page = historyPage(params.page, selected ? 5001 : 2001);
  const query = (params.q ?? "").trim().slice(0, 200);
  const result = selected
    ? await context.client.rpc("entry_history", {
        p_entry_id: selected,
        p_limit: 20,
        p_offset: (page - 1) * 20,
      })
    : await context.client.rpc("entry_history_index", {
        p_query: query,
        p_limit: 50,
        p_offset: (page - 1) * 50,
      });
  const rows = (selected ? [] : (result.data ?? [])) as HistoryIndexEntry[];
  return (
    <WorkspaceShell activeDestination="library" viewer={context.viewer}>
      <div className={styles.workspace}>
        <header>
          <p className={styles.eyebrow}>NOTHING GOOD HAS TO BE LOST</p>
          <h1>Entry history</h1>
          <p>
            Revisit earlier words and metadata. Restoring saves your current
            version first.
          </p>
        </header>
        {result.error ? (
          <p role="alert">History could not load. Refresh to try again.</p>
        ) : selected ? (
          result.data ? (
            <EntryHistoryView
              key={`${selected}:${(result.data as EntryHistory).current.revision}:${page}`}
              history={result.data as EntryHistory}
              page={page}
              ownerId={context.viewer.id}
            />
          ) : (
            <p>
              This Entry is no longer available.{" "}
              <Link href="/history">Back to history</Link>
            </p>
          )
        ) : (
          <>
            <form className={styles.search}>
              <label htmlFor="history-search">Find an Entry</label>
              <div>
                <input
                  id="history-search"
                  name="q"
                  defaultValue={query}
                  maxLength={200}
                  placeholder="Title or words in the current Entry"
                />
                <button>Search history</button>
              </div>
            </form>
            {rows.length === 0 ? (
              <p className={styles.empty}>
                No matching history yet. Earlier versions appear after an Entry
                is edited.
              </p>
            ) : (
              <div className={styles.list}>
                {rows.map((row) => (
                  <Link
                    href={`/history?entry=${row.entry_id}`}
                    key={row.entry_id}
                  >
                    <strong>{historyTitle(row)}</strong>
                    <span>
                      {row.entry_type.replaceAll("_", " ")} ·{" "}
                      {row.version_count} earlier versions
                      {row.is_deleted ? " · In Trash" : ""}
                    </span>
                    <p>{row.excerpt}</p>
                  </Link>
                ))}
              </div>
            )}
            <nav className={styles.pagination} aria-label="History pages">
              {page > 1 && (
                <Link
                  href={`/history?q=${encodeURIComponent(query)}&page=${page - 1}`}
                >
                  Newer Entries
                </Link>
              )}
              <span>Page {page}</span>
              {(rows[0]?.total_count ?? 0) > page * 50 && (
                <Link
                  href={`/history?q=${encodeURIComponent(query)}&page=${page + 1}`}
                >
                  Older Entries
                </Link>
              )}
            </nav>
          </>
        )}
      </div>
    </WorkspaceShell>
  );
}
