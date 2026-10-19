import Link from "next/link";
import { useId, type ReactNode } from "react";
import {
  entryRowDefaults,
  type EntryRowVariant,
} from "@/generated/design-system";
import { ProgressiveImage } from "@/components/progressive-image";
import { SeparatedList } from "@/components/separated-list";
import styles from "./entry-row.module.css";

export type EntryRowThumbnail = {
  alt: string;
  /** A thumbnail address, or null when the photo cannot be shown. */
  src: string | null;
};

export type EntryRowProps = {
  /** Where the row leads, normally the Entry's Item page. */
  href: string;
  /**
   * The row's serif title. For an untitled Entry pass its date, as entryRowLabels() does,
   * and leave `date` null.
   */
  title: string;
  /**
   * The text in the 112px date column, such as "Oct 17", "Fall 2025", or "Jan 2026 - now".
   * Null leaves the column empty, as for an untitled Entry titled by its date.
   */
  date: string | null;
  /** The machine-readable date for the date column's `<time>` element. */
  dateTime?: string | null;
  /** One line of the Entry's writing, or a highlighted search snippet. */
  excerpt?: ReactNode;
  /** Tag names, shown as quiet `#tag` text. */
  tags?: readonly string[];
  /** Marks the row with the green Chapter icon. */
  isChapter?: boolean;
  /** Marks the row with the warm First Time icon. */
  isFirstTime?: boolean;
  /** A 48px photo at the row's end, such as the Entry's first photo. */
  thumbnail?: EntryRowThumbnail | null;
  /** Why a search result matched, such as Title or Meaning, shown under the excerpt. */
  matchReasons?: readonly string[];
  /** Controls beside the row and outside its link, such as Restore and Delete in Trash. */
  actions?: ReactNode;
  /** `compact` tightens the row for dense lists. */
  variant?: EntryRowVariant;
};

/**
 * One Entry in a list: a muted date column, a one-line serif title with the Chapter and First
 * Time marks, a one-line excerpt, quiet tags, and an optional photo. Library, Dashboard, a
 * Chapter's page, and Trash all draw Entries with it. Below 560px of list width the date moves
 * above the title. Render it inside EntryRowList or EntryRowGroup.
 * Specified in packages/design-system/components/entry-row.yaml.
 */
export function EntryRow({
  actions,
  date,
  dateTime,
  excerpt,
  href,
  isChapter = false,
  isFirstTime = false,
  matchReasons,
  tags,
  thumbnail,
  title,
  variant = entryRowDefaults.variant,
}: EntryRowProps) {
  const id = useId();
  const described = [
    date ? `${id}-date` : null,
    excerpt ? `${id}-excerpt` : null,
    tags?.length ? `${id}-tags` : null,
    matchReasons?.length ? `${id}-match` : null,
  ].filter(Boolean);

  return (
    <li
      className={styles.item}
      data-actions={actions ? "true" : undefined}
      data-chapter={isChapter ? "true" : undefined}
      data-first-time={isFirstTime ? "true" : undefined}
      data-thumbnail={thumbnail ? "true" : undefined}
      data-ui-entry-row
      data-undated-title={date ? undefined : "true"}
      data-variant={variant}
    >
      <Link
        aria-describedby={described.length ? described.join(" ") : undefined}
        aria-labelledby={`${id}-title`}
        className={styles.row}
        href={href}
      >
        <span className={styles.date} id={`${id}-date`}>
          {date ? <time dateTime={dateTime ?? undefined}>{date}</time> : null}
        </span>
        <span className={styles.body}>
          <span className={styles.title} id={`${id}-title`}>
            {isChapter ? <ChapterMark /> : null}
            {isFirstTime ? <FirstTimeMark /> : null}
            <span className={styles.titleText}>{title}</span>
          </span>
          {excerpt ? (
            <span className={styles.excerpt} id={`${id}-excerpt`}>
              {excerpt}
            </span>
          ) : null}
          {tags?.length ? (
            <span className={styles.tags} id={`${id}-tags`}>
              {tags.map((tag) => `#${tag}`).join(" ")}
            </span>
          ) : null}
          {matchReasons?.length ? (
            <span className={styles.match} id={`${id}-match`}>
              <span>Matched in</span>
              <SeparatedList className={styles.matchReasons} spacing="word">
                {matchReasons.map((reason) => (
                  <span key={reason}>{reason}</span>
                ))}
              </SeparatedList>
            </span>
          ) : null}
        </span>
        {thumbnail ? (
          <ProgressiveImage
            alt={thumbnail.alt}
            className={styles.thumbnail}
            fallback={null}
            loading="lazy"
            src={thumbnail.src ?? undefined}
          />
        ) : null}
      </Link>
      {actions ? <div className={styles.actions}>{actions}</div> : null}
    </li>
  );
}

/**
 * Rows in one ruled list. Name it with `label`, or with `labelledBy` when a heading above it
 * already does.
 */
export function EntryRowList({
  children,
  className,
  label,
  labelledBy,
}: {
  children: ReactNode;
  className?: string;
  label?: string;
  labelledBy?: string;
}) {
  return (
    <ul
      aria-label={label}
      aria-labelledby={labelledBy}
      className={[styles.list, className].filter(Boolean).join(" ")}
      data-entry-list
      data-ui-entry-row-list
    >
      {children}
    </ul>
  );
}

/**
 * Rows under a quiet heading, such as a month in a list ordered by the date things happened.
 */
export function EntryRowGroup({
  children,
  headingLevel = 2,
  label,
}: {
  children: ReactNode;
  headingLevel?: 2 | 3;
  label: string;
}) {
  const id = useId();
  const Heading = headingLevel === 2 ? "h2" : "h3";
  return (
    <section aria-labelledby={id} className={styles.group}>
      <Heading className={styles.groupHeading} id={id}>
        {label}
      </Heading>
      <EntryRowList labelledBy={id}>{children}</EntryRowList>
    </section>
  );
}

/** The green mark of a Chapter, named for assistive technology. */
export function ChapterMark() {
  return (
    <svg
      aria-label="Chapter"
      className={styles.mark}
      data-mark="chapter"
      role="img"
      viewBox="0 0 24 24"
    >
      <path
        d="M5 6v12M19 6v12M5 12h14"
        fill="none"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth="1.8"
      />
    </svg>
  );
}

/** The warm mark of a First Time, named for assistive technology. */
export function FirstTimeMark() {
  return (
    <svg
      aria-label="First Time"
      className={styles.mark}
      data-mark="first-time"
      role="img"
      viewBox="0 0 24 24"
    >
      <path
        d="M12 3.5l2 5.5 5.5 2-5.5 2-2 5.5-2-5.5-5.5-2 5.5-2z"
        fill="currentColor"
      />
    </svg>
  );
}
