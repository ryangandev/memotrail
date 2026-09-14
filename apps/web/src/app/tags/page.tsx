import Link from "next/link";
import { Icon } from "@/components/icon";
import { OrganizationControl } from "@/components/organization-control";
import { PageFrame } from "@/components/page-frame";
import { getOrganizationWorkspace } from "@/lib/data/organization-workspace";
import styles from "./page.module.css";

export const dynamic = "force-dynamic";

export default async function TagsPage({
  searchParams,
}: {
  searchParams: Promise<{ page?: string; q?: string }>;
}) {
  const params = await searchParams;
  const query = (params.q ?? "").trim().slice(0, 200);
  const candidatePage = Number(params.page ?? 1);
  const page =
    Number.isSafeInteger(candidatePage) && candidatePage > 0
      ? candidatePage
      : 1;
  const workspace = await getOrganizationWorkspace({
    kind: "tag",
    page,
    query,
  });
  if (!workspace) return null;

  return (
    <PageFrame variant="standard">
      <header className={styles.pageHeader}>
        <div>
          <p className={styles.eyebrow}>Filter across your archive</p>
          <h1>Tags</h1>
          <p>
            Tags are lightweight descriptors such as travel, family, or funny.
            Use them across Entry types when you want a flexible filter, not a
            curated chapter.
          </p>
        </div>
        <OrganizationControl items={workspace.items} kind="tag" />
      </header>

      <form className={styles.search}>
        <label htmlFor="tag-search">Find a tag</label>
        <div>
          <input
            defaultValue={query}
            id="tag-search"
            maxLength={200}
            name="q"
            placeholder="Search tag names"
          />
          <button type="submit">
            <Icon name="search" size={17} />
            Search
          </button>
        </div>
      </form>

      {workspace.loadError ? (
        <div className={styles.message} role="alert">
          <Icon name="tag" size={22} />
          <div>
            <strong>Tags unavailable</strong>
            <p>{workspace.loadError}</p>
          </div>
        </div>
      ) : workspace.items.length === 0 ? (
        <div className={styles.emptyState}>
          <span>
            <Icon name="tag" size={22} />
          </span>
          <strong>{query ? "No matching tags" : "No tags yet"}</strong>
          <p>
            {query
              ? "Try a different name or clear your search."
              : "Add a tag here or while editing any Entry. It will become available everywhere."}
          </p>
        </div>
      ) : (
        <section className={styles.tagList} aria-label="Tags">
          <div className={styles.summary}>
            <span>{countLabel(workspace.totalCount, "tag")}</span>
            <span>Names apply everywhere they are used</span>
          </div>
          {workspace.items.map((item) => (
            <article className={styles.tagRow} key={item.id}>
              <Link href={`/search?tag=${encodeURIComponent(item.name)}`}>
                <span className={styles.tagMark}>#</span>
                <div>
                  <h2>{item.name}</h2>
                  <p>
                    {item.entry_count
                      ? `Used by ${countLabel(item.entry_count, "Entry")}`
                      : "Not used by an Entry yet"}
                  </p>
                </div>
                <span className={styles.openLabel}>Browse Entries</span>
                <Icon name="chevron" size={16} />
              </Link>
              <OrganizationControl
                item={item}
                items={workspace.items}
                kind="tag"
              />
            </article>
          ))}
        </section>
      )}

      <Pagination page={page} query={query} totalCount={workspace.totalCount} />
    </PageFrame>
  );
}

function Pagination({
  page,
  query,
  totalCount,
}: {
  page: number;
  query: string;
  totalCount: number;
}) {
  const hasPrevious = page > 1;
  const hasNext = page * 50 < totalCount;
  if (!hasPrevious && !hasNext) return null;

  const href = (nextPage: number) =>
    `/tags?${new URLSearchParams({ page: String(nextPage), q: query })}`;

  return (
    <nav className={styles.pagination} aria-label="Tag pages">
      {hasPrevious ? <Link href={href(page - 1)}>Previous</Link> : <span />}
      <span>Page {page}</span>
      {hasNext ? <Link href={href(page + 1)}>Next</Link> : <span />}
    </nav>
  );
}

function countLabel(count: number, singular: string) {
  return `${count} ${count === 1 ? singular : `${singular}s`}`;
}
