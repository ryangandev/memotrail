import { EntryRow, EntryRowList } from "@/components/entry-row";

export type EntryListItem = {
  /** A thumbnail, such as an Entry's first photo. */
  cover?: { alt: string; src: string | null } | null;
  /** The date to show beside the title, or null when the title already is the date. */
  date: string | null;
  excerpt: string;
  href: string;
  id: string;
  isChapter: boolean;
  isFirstTime: boolean;
  /** The title, or the date for an Entry without one. */
  title: string;
};

/**
 * A list of Entries drawn with EntryRow.
 *
 * @deprecated Render EntryRowList and EntryRow from `@/components/entry-row` directly, with
 * entryRowLabels() from `@/lib/data/entry-row` for the title and date. This wrapper keeps a
 * Chapter's page working until it moves to EntryRow.
 */
export function EntryList({
  items,
  label,
}: {
  items: readonly EntryListItem[];
  label: string;
}) {
  return (
    <EntryRowList label={label}>
      {items.map((item) => (
        <EntryRow
          date={item.date}
          excerpt={item.excerpt || null}
          href={item.href}
          isChapter={item.isChapter}
          isFirstTime={item.isFirstTime}
          key={item.id}
          thumbnail={item.cover ?? null}
          title={item.title}
        />
      ))}
    </EntryRowList>
  );
}
