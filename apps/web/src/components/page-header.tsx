import type { ReactNode } from "react";
import type { WorkspaceDestination } from "@/lib/workspace-destinations";
import { PageBackLink } from "./workspace-destination";
import styles from "./page-header.module.css";

/**
 * A page's title block: a contextual back link on a detail page, the serif title, one optional
 * muted meta line, and at most one primary action. A page explains itself through its content,
 * so the header has no eyebrow and no description.
 * Specified in packages/design-system/components/page-header.yaml.
 */
export function PageHeader({
  action,
  back,
  headingLevel = 1,
  meta,
  title,
}: {
  title: ReactNode;
  /** One short muted line under the title, such as a count, a date span, or facts. */
  meta?: ReactNode;
  /** The page's one primary action, at the title's trailing edge. */
  action?: ReactNode;
  /** On a detail page, the destination it belongs to: the back link leads there and marks it active. */
  back?: WorkspaceDestination;
  headingLevel?: 1 | 2;
}) {
  const Heading = headingLevel === 1 ? "h1" : "h2";
  return (
    <header
      className={styles.header}
      data-detail={back ? "true" : undefined}
      data-ui-page-header
    >
      {back ? <PageBackLink destination={back} /> : null}
      <div className={styles.row}>
        <div className={styles.copy}>
          <Heading className={styles.title}>{title}</Heading>
          {meta ? <div className={styles.meta}>{meta}</div> : null}
        </div>
        {action ? <div className={styles.action}>{action}</div> : null}
      </div>
    </header>
  );
}
