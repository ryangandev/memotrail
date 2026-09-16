import Link from "next/link";
import { EntryHistoryView } from "@/components/entry-history-view";
import { PageFrame } from "@/components/page-frame";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  historyTitle,
  historyPage,
  validHistoryID,
  type EntryHistory,
  type HistoryIndexEntry,
} from "@/lib/data/history";
import { wikiItemIdentityLabel } from "@/lib/data/wiki-item";
import styles from "./page.module.css";
export const dynamic = "force-dynamic";
export default async function HistoryPage({
  searchParams,
}: {
  searchParams: Promise<{ entry?: string; page?: string; q?: string }>;
}) {
  const context = await getAuthenticatedContext();
  if (!context) return null;
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
    <PageFrame className={styles.workspace} variant="wide">
      <header>
        <p className={styles.eyebrow}>NOTHING GOOD HAS TO BE LOST</p>
        <h1>Version history</h1>
        <p>
          Revisit earlier versions of anything in your Life Wiki. Restoring
          always keeps the current version first.
        </p>
      </header>
      {result.error ? (
        <p role="alert">History could not load. Refresh to try again.</p>
      ) : selected ? (
        result.data ? (
          <EntryHistoryView
            key={`${selected}:${page}`}
            history={result.data as EntryHistory}
            page={page}
            ownerId={context.viewer.id}
          />
        ) : (
          <p>
            This item is no longer available.{" "}
            <Link href="/history">Back to history</Link>
          </p>
        )
      ) : (
        <>
          <form className={styles.search}>
            <label htmlFor="history-search">Find an item</label>
            <div>
              <input
                id="history-search"
                name="q"
                defaultValue={query}
                maxLength={200}
                placeholder="Title or words in the current item"
              />
              <button>Search history</button>
            </div>
          </form>
          {rows.length === 0 ? (
            <p className={styles.empty}>
              No matching history yet. Earlier versions appear after an item is
              edited.
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
                    {wikiItemIdentityLabel(row.item_kind, row.item_subtype)} ·{" "}
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
                Newer items
              </Link>
            )}
            <span>Page {page}</span>
            {(rows[0]?.total_count ?? 0) > page * 50 && (
              <Link
                href={`/history?q=${encodeURIComponent(query)}&page=${page + 1}`}
              >
                Older items
              </Link>
            )}
          </nav>
        </>
      )}
    </PageFrame>
  );
}
