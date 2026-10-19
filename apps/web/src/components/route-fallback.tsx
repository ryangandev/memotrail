import type { ReactNode } from "react";
import { PageFrame } from "@/components/page-frame";
import { PageHeader } from "@/components/page-header";
import styles from "./route-fallback.module.css";

/**
 * What a route shows in place of its page when it cannot: a missing page, an Entry that is
 * gone, or a failure. It is an ordinary page header, one sentence, and the way onward, inside
 * the workspace shell where there is one, so every dead end looks the same.
 */
export function RouteFallback({
  actions,
  description,
  title,
}: {
  /** The way onward: one primary ButtonLink or Button, and at most one secondary. */
  actions: ReactNode;
  /** One sentence that says what happened. */
  description: ReactNode;
  title: ReactNode;
}) {
  return (
    <PageFrame data-route-fallback width="reading">
      <PageHeader meta={description} title={title} />
      <div className={styles.actions}>{actions}</div>
    </PageFrame>
  );
}
