import type { ReactNode } from "react";
import { PageFrame } from "./page-frame";
import { PageHeader } from "./page-header";
import styles from "./focused-view-layout.module.css";

export function FocusedViewLayout({
  actions,
  children,
  description,
  eyebrow,
  summary,
  summaryLabel,
  title,
}: {
  actions: ReactNode;
  children: ReactNode;
  description: ReactNode;
  eyebrow: ReactNode;
  summary: ReactNode;
  summaryLabel: string;
  title: ReactNode;
}) {
  return (
    <PageFrame variant="wide">
      <PageHeader
        actions={actions}
        description={description}
        eyebrow={eyebrow}
        title={title}
      />
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
