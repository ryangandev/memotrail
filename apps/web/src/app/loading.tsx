import { PageFrame } from "@/components/page-frame";
import { Skeleton } from "@/components/skeleton";
import styles from "./loading.module.css";

/**
 * The route loading fallback. It holds the shape of a PageHeader (a title line and a meta line)
 * above a few list rows, in the list frame, so the page settles without the title jumping.
 * Heights come from the Web layout variables in globals.css that size the real header.
 */
export default function Loading() {
  return (
    <PageFrame
      aria-label="Loading page"
      aria-live="polite"
      role="status"
      width="list"
    >
      <div className={styles.header}>
        <Skeleton
          height="calc(var(--page-title-size) * var(--page-title-line-height))"
          width="min(60%, 320px)"
        />
        <Skeleton
          height="calc(var(--page-meta-size) * var(--mt-line-height-message))"
          width="min(40%, 200px)"
        />
      </div>
      <div className={styles.rows}>
        <Skeleton height="var(--mt-size-control-large)" />
        <Skeleton height="var(--mt-size-control-large)" />
        <Skeleton height="var(--mt-size-control-large)" />
      </div>
    </PageFrame>
  );
}
