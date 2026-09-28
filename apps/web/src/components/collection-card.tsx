import Link from "next/link";
import type { ReactNode } from "react";
import { Icon } from "@/components/icon";
import styles from "./collection-card.module.css";

export function CollectionCard({
  entryCount,
  href,
  headingLevel = "h2",
  inboxCount = 0,
  manageAction,
  name,
  updatedLabel,
}: {
  entryCount: number;
  href: string;
  headingLevel?: "h2" | "h4";
  inboxCount?: number;
  manageAction?: ReactNode;
  name: string;
  updatedLabel?: string;
}) {
  const Heading = headingLevel;
  return (
    <article className={styles.card} data-collection-card>
      <Link className={styles.link} href={href}>
        <span className={styles.topline}>
          <Icon name="archive" size={17} />
          <span>Collection</span>
        </span>
        <Heading className={styles.title} title={name}>
          {name}
        </Heading>
        <span className={styles.bottomline}>
          <span>
            {entryCount} {entryCount === 1 ? "Entry" : "Entries"}
            {inboxCount > 0 ? ` · ${inboxCount} in Inbox` : ""}
          </span>
          <Icon name="chevron" size={14} />
        </span>
        <span className={styles.updated}>
          {updatedLabel ?? "Ready for its first Entry"}
        </span>
      </Link>
      {manageAction ? (
        <div className={styles.manage}>{manageAction}</div>
      ) : null}
    </article>
  );
}
