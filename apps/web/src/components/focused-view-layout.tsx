import type { ReactNode } from "react";
import { PageFrame } from "./page-frame";
import { PageHeader } from "./page-header";
import styles from "./focused-view-layout.module.css";

export function FocusedViewLayout({
  action,
  children,
  summary,
  summaryLabel,
  title,
}: {
  /** The view's one primary action, beside the title. */
  action: ReactNode;
  children: ReactNode;
  summary: ReactNode;
  summaryLabel: string;
  title: ReactNode;
}) {
  return (
    <PageFrame width="list">
      <PageHeader action={action} title={title} />
      <div
        aria-label={summaryLabel}
        className={styles.summary}
        data-focused-view-summary
      >
        {summary}
      </div>
      <div className={styles.content} data-focused-view-content>
        {children}
      </div>
    </PageFrame>
  );
}
