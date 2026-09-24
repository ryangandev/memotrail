import Link from "next/link";
import { Icon } from "@/components/icon";
import { IconButton } from "@/components/button";
import styles from "./collection-card-concept.module.css";

export function CollectionCardConcept({
  entryCount,
  href,
  inboxCount = 0,
  name,
  onManage,
  updatedLabel,
}: {
  entryCount: number;
  href: string;
  inboxCount?: number;
  name: string;
  onManage?: () => void;
  updatedLabel?: string;
}) {
  return (
    <article className={styles.card} data-collection-card-concept>
      <Link className={styles.link} href={href}>
        <span className={styles.topline}>
          <Icon name="archive" size={17} />
          <span>Collection</span>
        </span>
        <h4 title={name}>{name}</h4>
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
      {onManage ? (
        <IconButton
          className={styles.manage}
          label={`Manage ${name}`}
          onClick={onManage}
          size="small"
          variant="ghost"
        >
          <Icon name="more" size={17} />
        </IconButton>
      ) : null}
    </article>
  );
}
