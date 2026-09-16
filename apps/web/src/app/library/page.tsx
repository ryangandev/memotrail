import Link from "next/link";
import { Icon } from "@/components/icon";
import { PageFrame } from "@/components/page-frame";
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

const availableDestinations = [
  {
    detail:
      "Keep a complete portable copy, including history and original photos.",
    href: "/settings/export",
    icon: "archive" as const,
    title: "Export archive",
  },
  {
    detail: "Inspect earlier writing and safely restore versions.",
    href: "/history",
    icon: "archive" as const,
    title: "Entry history",
  },
  {
    detail: "Control optional AI assistance, privacy, and spending.",
    href: "/settings/ai",
    icon: "sparkle" as const,
    title: "AI settings",
  },
  {
    detail: "Connect the people who shaped your story.",
    href: "/people",
    icon: "archive" as const,
    title: "People",
  },
  {
    detail: "Browse the themes that connect your Entries.",
    href: "/collections",
    icon: "archive" as const,
    title: "Collections",
  },
  {
    detail: "Filter every kind of Entry with lightweight shared descriptors.",
    href: "/tags",
    icon: "tag" as const,
    title: "Tags",
  },
  {
    detail: "Revisit the experiences you tried, saw, or learned first.",
    href: "/first-times",
    icon: "star" as const,
    title: "First Times",
  },
  {
    detail:
      "Revisit the locations connected to your writing, events, and Homes.",
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
    detail: "Keep active plans, distant hopes, and someday ideas close.",
    href: "/goals",
    icon: "target" as const,
    title: "Goals",
  },
];

const plannedDestinations: string[] = [];

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
    <PageFrame className={styles.content} variant="compact">
      <header className={styles.header}>
        <p>Your personal archive</p>
        <h1>Library</h1>
        <span>
          Browse the Writings, Entities, Events, Stories, and Goals that make up
          your Life Wiki.
        </span>
      </header>

      <section aria-labelledby="all-items-heading">
        <div className={styles.sectionHeading}>
          <h2 id="all-items-heading">All items</h2>
          <span>
            {totalCount} {totalCount === 1 ? "item" : "items"}
          </span>
        </div>
        <form className={styles.wikiFilters}>
          <label>
            <span>Find in your Life Wiki</span>
            <input
              defaultValue={query}
              maxLength={200}
              name="q"
              placeholder="Search titles, writing, people, or places"
              type="search"
            />
          </label>
          <label>
            <span>Kind</span>
            <select defaultValue={itemKind ?? ""} name="kind">
              <option value="">All Kinds</option>
              <option value="capture">Captures</option>
              <option value="writing">Writing</option>
              <option value="entity">Entities</option>
              <option value="event">Events</option>
              <option value="story">Stories</option>
              <option value="goal">Goals</option>
            </select>
          </label>
          <button type="submit">Browse</button>
        </form>

        {workspace.error ? (
          <p role="alert">{workspace.error}</p>
        ) : workspace.items.length === 0 ? (
          <div className={styles.wikiEmpty}>
            <strong>No matching items</strong>
            <p>Try another phrase or Kind, or capture something new.</p>
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
                  <span>
                    {wikiItemSubtypeLabel(item.itemKind, item.itemSubtype)}
                  </span>
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

      <section aria-labelledby="available-library-heading">
        <div className={styles.sectionHeading}>
          <h2 id="available-library-heading">Browse by structure</h2>
          <span>Focused records and archive tools</span>
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

      {plannedDestinations.length > 0 ? (
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
      ) : null}
    </PageFrame>
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
