import type { ComponentPropsWithoutRef, ReactNode } from "react";
import styles from "./section-header.module.css";

type SectionHeaderProps = Omit<ComponentPropsWithoutRef<"div">, "title"> & {
  title: ReactNode;
  /** A quiet count or note beside the title, or at the far edge with `detailAlign="end"`. */
  detail?: ReactNode;
  detailAlign?: "start" | "end";
  /** One explanatory sentence under the title. */
  description?: ReactNode;
  /** A link or button at the trailing edge. */
  action?: ReactNode;
  /** `section` is a serif title for a region of content; `list` is the small uppercase heading above a list. */
  variant?: "section" | "list";
  /** Chosen by the caller to fit the page outline. */
  headingLevel?: 2 | 3 | 4;
  /** Lets the region name itself with `aria-labelledby`. */
  headingId?: string;
};

/** The heading of a region of a page: a title with optional detail, description, and action. */
export function SectionHeader({
  action,
  className,
  description,
  detail,
  detailAlign = "start",
  headingId,
  headingLevel = 2,
  title,
  variant = "section",
  ...props
}: SectionHeaderProps) {
  const Heading = `h${headingLevel}` as "h2" | "h3" | "h4";
  const detailNode = detail ? (
    <span className={styles.detail}>{detail}</span>
  ) : null;
  const trailing = detailAlign === "end" ? detailNode : null;
  return (
    <div
      {...props}
      className={[styles.header, className].filter(Boolean).join(" ")}
      data-stacked={description ? "true" : undefined}
      data-ui-section-header
      data-variant={variant}
    >
      <div className={styles.copy}>
        <div className={styles.heading}>
          <Heading className={styles.title} id={headingId}>
            {title}
          </Heading>
          {detailAlign === "start" ? detailNode : null}
        </div>
        {description ? (
          <p className={styles.description}>{description}</p>
        ) : null}
      </div>
      {trailing || action ? (
        <div className={styles.trailing}>
          {trailing}
          {action}
        </div>
      ) : null}
    </div>
  );
}
