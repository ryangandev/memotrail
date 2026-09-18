import { EmptyState } from "@/components/empty-state";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/button";
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
      <PageHeader
        title={<>Tags</>}
        eyebrow={<>Filter across your archive</>}
        description={
          <>
            Tags are lightweight descriptors such as travel, family, or funny.
            Use them across Entry types when you want a flexible filter, not a
            curated chapter.
          </>
        }
        actions={
          <>
            <OrganizationControl items={workspace.items} kind="tag" />
          </>
        }
      />

      <form aria-label="Find tags" className={styles.search} role="search">
        <label className={styles.visuallyHidden} htmlFor="tag-search">
          Find a tag
        </label>
        <div>
          <input
            defaultValue={query}
            id="tag-search"
            maxLength={200}
            name="q"
            placeholder="Search tag names"
          />
          <Button variant="primary" type="submit">
            <Icon name="search" size={17} />
            Search
          </Button>
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
        <EmptyState
          title={<>{query ? "No matching tags" : "No tags yet"}</>}
          description={
            <>
              <Icon name="tag" size={22} />
              {query
                ? "Try a different name or clear your search."
                : "Add a tag here or while editing any Entry. It will become available everywhere."}
            </>
          }
        />
      ) : (
        <section className={styles.tagList} aria-label="Tags">
          <div className={styles.summary}>
            <span>{countLabel(workspace.totalCount, "tag")}</span>
          </div>
          <div className={styles.tagCloud}>
            {workspace.items.map((item) => (
              <article className={styles.tagBadge} key={item.id}>
                <OrganizationControl
                  item={item}
                  items={workspace.items}
                  kind="tag"
                  trigger={
                    <>
                      <span className={styles.tagMark} aria-hidden="true">
                        #
                      </span>
                      <span className={styles.tagName}>{item.name}</span>
                      <span
                        aria-label={countLabel(item.entry_count, "Entry")}
                        className={styles.tagCount}
                      >
                        {item.entry_count}
                      </span>
                    </>
                  }
                  triggerClassName={styles.tagTrigger}
                />
              </article>
            ))}
          </div>
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
