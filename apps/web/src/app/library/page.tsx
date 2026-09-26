import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/button";
import Link from "next/link";
import { Icon, type IconName } from "@/components/icon";
import { PageFrame } from "@/components/page-frame";
import { SearchField } from "@/components/search-field";
import { SelectField } from "@/components/select-field";
import {
  isWikiItemKind,
  wikiItemKindLabel,
  wikiItemSubtypeLabel,
} from "@/lib/data/wiki-item";
import {
  getWikiItemsWorkspace,
  wikiItemHref,
  wikiItemsPage,
} from "@/lib/data/wiki-items";
import styles from "./page.module.css";

export const dynamic = "force-dynamic";

type LibraryDestination = {
  detail: string;
  href: string;
  icon: IconName;
  title: string;
};

const focusedDestinations: LibraryDestination[] = [
  {
    detail: "Connect the people who shaped your life.",
    href: "/people",
    icon: "person" as const,
    title: "People",
  },
  {
    detail: "Remember every place you called home and when it was yours.",
    href: "/homes",
    icon: "home" as const,
    title: "Homes",
  },
  {
    detail: "Remember every vehicle and the time it was part of your life.",
    href: "/vehicles",
    icon: "car" as const,
    title: "Vehicles",
  },
  {
    detail: "Explore the memories and events tied to coordinates on a map.",
    href: "/map",
    icon: "map" as const,
    title: "Map",
  },
  {
    detail: "Revisit the experiences you tried, saw, or learned first.",
    href: "/first-times",
    icon: "star" as const,
    title: "First Times",
  },
  {
    detail: "Keep active plans, distant hopes, and someday ideas close.",
    href: "/goals",
    icon: "target" as const,
    title: "Goals",
  },
];

const organizationDestinations: LibraryDestination[] = [
  {
    detail: "Curate records into meaningful groups.",
    href: "/collections",
    icon: "archive" as const,
    title: "Collections",
  },
  {
    detail: "Use lightweight descriptors to reconnect related items.",
    href: "/tags",
    icon: "tag" as const,
    title: "Tags",
  },
];

const archiveDestinations: LibraryDestination[] = [
  {
    detail: "Inspect earlier versions and restore one without losing today.",
    href: "/history",
    icon: "clock" as const,
    title: "Version history",
  },
  {
    detail: "Restore removed items or permanently clear them.",
    href: "/trash",
    icon: "trash" as const,
    title: "Trash",
  },
  {
    detail: "Keep a portable copy with history and original photos.",
    href: "/settings/export",
    icon: "archive" as const,
    title: "Export archive",
  },
];

export default async function LibraryPage({
  searchParams,
}: {
  searchParams: Promise<{
    kind?: string | string[];
    page?: string | string[];
    q?: string | string[];
  }>;
}) {
  const parameters = await searchParams;
  const query = firstParameter(parameters.q).trim().slice(0, 200);
  const requestedKind = firstParameter(parameters.kind);
  const itemKind = isWikiItemKind(requestedKind) ? requestedKind : null;
  const page = wikiItemsPage(firstParameter(parameters.page));
  const workspace = await getWikiItemsWorkspace({ itemKind, page, query });
  if (!workspace) return null;
  const totalCount = workspace.items[0]?.totalCount ?? 0;

  return (
    <PageFrame className={styles.content} variant="standard">
      <PageHeader
        title={<>Library</>}
        eyebrow={<>Your Life Wiki</>}
        description={
          <>
            One place for your Entries, people, homes, and goals.
          </>
        }
      />

      <section aria-labelledby="all-items-heading">
        <div className={styles.sectionHeading}>
          <h2 id="all-items-heading">
            {itemKind === "entity"
              ? "People, homes & vehicles"
              : itemKind
                ? wikiItemKindLabel(itemKind)
                : "All items"}
          </h2>
          <span>
            {totalCount} {totalCount === 1 ? "item" : "items"}
          </span>
        </div>
        <form className={styles.wikiFilters}>
          <SearchField
            defaultValue={query}
            label="Find in your Life Wiki"
            maxLength={200}
            name="q"
            placeholder="Search titles, writing, or people"
          />
          <SelectField defaultValue={itemKind ?? ""} label="Show" name="kind">
              <option value="">All records</option>
              <option value="entry">Entries</option>
              <option value="entity">People, homes & vehicles</option>
              <option value="goal">Goals</option>
          </SelectField>
          <Button variant="primary" type="submit">
            Apply
          </Button>
        </form>

        {workspace.error ? (
          <p role="alert">{workspace.error}</p>
        ) : workspace.items.length === 0 ? (
          <div className={styles.wikiEmpty}>
            <strong>No matching items</strong>
            <p>Try another phrase or category, or capture something new.</p>
          </div>
        ) : (
          <div className={styles.wikiGrid}>
            {workspace.items.map((item) => (
              <Link
                href={wikiItemHref(item)}
                key={`${item.recordSource}:${item.id}`}
              >
                <div className={styles.wikiBadges}>
                  <span>{wikiItemKindLabel(item.itemKind)}</span>
                  {wikiItemSubtypeLabel(item.itemKind, item.itemSubtype) !==
                  wikiItemKindLabel(item.itemKind) ? (
                    <span>
                      {wikiItemSubtypeLabel(item.itemKind, item.itemSubtype)}
                    </span>
                  ) : null}
                </div>
                <strong>{item.title}</strong>
                {item.excerpt ? <p>{item.excerpt}</p> : null}
                <small>{wikiItemDateLabel(item)}</small>
              </Link>
            ))}
          </div>
        )}

        <nav className={styles.pagination} aria-label="Life Wiki pages">
          {page > 1 ? (
            <Link href={libraryPageHref(query, itemKind, page - 1)}>
              Newer items
            </Link>
          ) : (
            <span />
          )}
          <span>Page {page}</span>
          {totalCount > page * 36 ? (
            <Link href={libraryPageHref(query, itemKind, page + 1)}>
              Older items
            </Link>
          ) : (
            <span />
          )}
        </nav>
      </section>

      <section aria-labelledby="focused-library-heading">
        <div className={styles.sectionHeading}>
          <h2 id="focused-library-heading">Focused views</h2>
          <span>Structured parts of your life</span>
        </div>
        <DestinationGrid destinations={focusedDestinations} />
      </section>

      <div className={styles.libraryUtilities}>
        <section aria-labelledby="organize-library-heading">
          <div className={styles.sectionHeading}>
            <h2 id="organize-library-heading">Organize</h2>
            <span>Across your library</span>
          </div>
          <DestinationGrid destinations={organizationDestinations} />
        </section>

        <section aria-labelledby="archive-library-heading">
          <div className={styles.sectionHeading}>
            <h2 id="archive-library-heading">Archive tools</h2>
            <span>History, recovery, and export</span>
          </div>
          <DestinationGrid destinations={archiveDestinations} />
        </section>
      </div>
    </PageFrame>
  );
}

function DestinationGrid({
  destinations,
}: {
  destinations: LibraryDestination[];
}) {
  return (
    <div className={styles.destinationGrid}>
      {destinations.map((destination) => (
        <Link href={destination.href} key={destination.href}>
          <span>
            <Icon name={destination.icon} size={19} />
          </span>
          <div>
            <strong>{destination.title}</strong>
            <p>{destination.detail}</p>
          </div>
          <Icon name="chevron" size={14} />
        </Link>
      ))}
    </div>
  );
}

function firstParameter(value: string | string[] | undefined) {
  return Array.isArray(value) ? (value[0] ?? "") : (value ?? "");
}

function libraryPageHref(query: string, itemKind: string | null, page: number) {
  const parameters = new URLSearchParams();
  if (query) parameters.set("q", query);
  if (itemKind) parameters.set("kind", itemKind);
  if (page > 1) parameters.set("page", String(page));
  const value = parameters.toString();
  return value ? `/library?${value}` : "/library";
}

function wikiItemDateLabel(item: {
  occurredEnd: string | null;
  occurredStart: string | null;
  updatedAt: string;
}) {
  const format = (value: string) =>
    new Intl.DateTimeFormat("en", {
      dateStyle: "medium",
      timeZone: "UTC",
    }).format(new Date(value));
  if (item.occurredStart) {
    return item.occurredEnd
      ? `${format(item.occurredStart)} to ${format(item.occurredEnd)}`
      : format(item.occurredStart);
  }
  return `Updated ${format(item.updatedAt)}`;
}
