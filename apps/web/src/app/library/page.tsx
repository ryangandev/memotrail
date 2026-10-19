import { redirect } from "next/navigation";
import { LibrarySearch } from "@/components/library-search";
import { PageFrame } from "@/components/page-frame";
import { PageHeader } from "@/components/page-header";
import { getLibraryView, type LibraryView } from "@/lib/data/library";
import {
  parseSearchRequest,
  type RawSearchParams,
} from "@/lib/data/search-input";
import { wikiItemsPage } from "@/lib/data/wiki-items";
import styles from "./page.module.css";

export const dynamic = "force-dynamic";

export default async function LibraryPage({
  searchParams,
}: {
  searchParams: Promise<RawSearchParams>;
}) {
  const parameters = await searchParams;
  const parsed = parseSearchRequest({
    ...parameters,
    type: parameters.type ?? parameters.kind,
  });
  const page = wikiItemsPage(firstParameter(parameters.page));
  const view = await getLibraryView(parsed, page);
  if (!view) return null;
  // A page past the end, such as after Entries moved to Trash, opens the first page.
  if (!view.error && view.page > 1 && view.rows.length === 0) {
    redirect(view.mode === "browse" ? "/library" : firstPageHref(parameters));
  }

  return (
    <PageFrame width="list">
      <PageHeader meta={<LibraryMeta view={view} />} title="Library" />
      <LibrarySearch view={view} />
    </PageFrame>
  );
}

function LibraryMeta({ view }: { view: LibraryView }) {
  if (view.error) return null;
  const count = `${view.totalCount} ${view.totalCount === 1 ? "Entry" : "Entries"}`;
  if (view.mode === "browse") {
    if (view.totalCount === 0) return null;
    return (
      <>
        {count}, newest first
        <span className={styles.metaDetail}> by the date they happened</span>
      </>
    );
  }
  if (view.totalCount === 0) return null;
  const match = view.totalCount === 1 ? "matches" : "match";
  return view.mode === "search" ? (
    <>
      {count} {match}, best match first
    </>
  ) : (
    <>
      {count} {match}, newest first
      <span className={styles.metaDetail}> by the date they happened</span>
    </>
  );
}

function firstParameter(value: string | string[] | undefined) {
  return Array.isArray(value) ? (value[0] ?? "") : (value ?? "");
}

function firstPageHref(parameters: RawSearchParams) {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(parameters)) {
    if (key === "page" || value === undefined) continue;
    for (const item of Array.isArray(value) ? value : [value]) {
      search.append(key, item);
    }
  }
  const query = search.toString();
  return query ? `/library?${query}` : "/library";
}
