import { EmptyState } from "@/components/empty-state";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/button";
import Link from "next/link";
import { Icon } from "@/components/icon";
import { TagControl } from "@/components/tag-control";
import { PageFrame } from "@/components/page-frame";
import { SearchField } from "@/components/search-field";
import { getTagsWorkspace } from "@/lib/data/organization-workspace";
import styles from "./page.module.css";
import { countLabel } from "@/lib/count-label";

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
  const workspace = await getTagsWorkspace({ page, query });
  if (!workspace) return null;

  const totalPages = Math.max(1, Math.ceil(workspace.totalCount / pageSize));

  return (
    <PageFrame width="list">
      <PageHeader
        title="Tags"
        meta={
          workspace.loadError || workspace.totalCount === 0
            ? undefined
            : query
              ? `${countLabel(workspace.totalCount, "tag")} matching “${query}”`
              : countLabel(workspace.totalCount, "tag")
        }
        action={<TagControl items={workspace.items} />}
      />

      <form aria-label="Find tags" className={styles.search} role="search">
        <div>
          <SearchField
            defaultValue={query}
            hideLabel
            id="tag-search"
            label="Find a tag"
            maxLength={200}
            name="q"
            placeholder="Search tag names"
            size="large"
          />
          <Button variant="secondary" type="submit">
            Search
          </Button>
        </div>
      </form>

      {workspace.loadError ? (
        <div role="alert">
          <EmptyState
            title="Tags unavailable"
            description={workspace.loadError}
            icon={<Icon name="tag" size={20} />}
          />
        </div>
      ) : workspace.items.length === 0 ? (
        <EmptyState
          title={query ? "No matching tags" : "No tags yet"}
          description={
            query
              ? "Try a different name or clear your search."
              : "Add a tag here or while editing any Entry. It will become available everywhere."
          }
          icon={<Icon name="tag" size={20} />}
        />
      ) : (
        <section className={styles.tagList} aria-label="Tags">
          <ul className={styles.rows}>
            {workspace.items.map((item) => (
              <li className={styles.row} key={item.id}>
                <TagControl
                  item={item}
                  items={workspace.items}
                  trigger={
                    <>
                      <span className={styles.tagName}>
                        <span aria-hidden="true" className={styles.tagMark}>
                          #
                        </span>
                        {item.name}
                      </span>
                      <span className={styles.tagCount}>
                        {countLabel(item.entry_count, "Entry")}
                      </span>
                    </>
                  }
                  triggerClassName={styles.tagTrigger}
                />
              </li>
            ))}
          </ul>
        </section>
      )}

      <Pagination
        page={page}
        query={query}
        totalCount={workspace.totalCount}
        totalPages={totalPages}
      />
    </PageFrame>
  );
}

const pageSize = 50;

function Pagination({
  page,
  query,
  totalCount,
  totalPages,
}: {
  page: number;
  query: string;
  totalCount: number;
  totalPages: number;
}) {
  const hasPrevious = page > 1;
  const hasNext = page * pageSize < totalCount;
  if (!hasPrevious && !hasNext) return null;

  const href = (nextPage: number) =>
    `/tags?${new URLSearchParams({ page: String(nextPage), q: query })}`;

  return (
    <nav className={styles.pagination} aria-label="Tag pages">
      {hasPrevious ? <Link href={href(page - 1)}>Previous</Link> : <span />}
      <span>
        Page {page} of {totalPages}
      </span>
      {hasNext ? <Link href={href(page + 1)}>Next</Link> : <span />}
    </nav>
  );
}
