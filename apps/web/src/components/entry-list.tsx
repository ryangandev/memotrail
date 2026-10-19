import Link from "next/link";
import { Badge } from "@/components/badge";
import { ProgressiveImage } from "@/components/progressive-image";
import styles from "./entry-list.module.css";

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
 * Library's row for an Entry: a Chapter and First Time badge where they apply, the date, the
 * title, a short excerpt, and an optional photo. Library and a Chapter's page draw the same row.
 */
export function EntryList({
  items,
  label,
}: {
  items: readonly EntryListItem[];
  label: string;
}) {
  return (
    <ul aria-label={label} className={styles.list} data-entry-list>
      {items.map((item) => (
        <li data-cover={item.cover ? "" : undefined} key={item.id}>
          <Link href={item.href}>
            {item.isChapter || item.isFirstTime || item.date ? (
              <div className={styles.meta}>
                {item.isChapter || item.isFirstTime ? (
                  <div className={styles.badges}>
                    {item.isChapter ? (
                      <Badge size="micro" uppercase>
                        Chapter
                      </Badge>
                    ) : null}
                    {item.isFirstTime ? (
                      <Badge size="micro" tone="neutral" uppercase>
                        First Time
                      </Badge>
                    ) : null}
                  </div>
                ) : null}
                {item.date ? <small>{item.date}</small> : null}
              </div>
            ) : null}
            <strong>{item.title}</strong>
            {item.excerpt ? <p>{item.excerpt}</p> : null}
            {item.cover ? (
              <ProgressiveImage
                alt={item.cover.alt}
                className={styles.cover}
                loading="lazy"
                src={item.cover.src ?? undefined}
              />
            ) : null}
          </Link>
        </li>
      ))}
    </ul>
  );
}
