import Link from "next/link";
import type {
  TimelineDisplayItem,
  TimelineDisplayModel,
} from "@/lib/data/timeline-presentation";
import { timelineEntryTypeLabel } from "@/lib/data/timeline-presentation";
import { wikiEntryHref } from "@/lib/data/wiki-item";
import styles from "./vertical-spine.module.css";

function SpineCard({ item }: { item: TimelineDisplayItem }) {
  return (
    <Link
      aria-label={`${item.entry.title}, ${item.dateLabel}, ${item.laneName}`}
      className={`${styles.card} ${item.entry.shape === "period" ? styles.period : ""}`}
      href={wikiEntryHref(item.entry)}
    >
      <span className={styles.date}>{item.dateLabel}</span>
      <strong>{item.entry.title}</strong>
      {item.entry.body ? (
        <span className={styles.body}>{item.entry.body}</span>
      ) : null}
      <span className={styles.cardFooter}>
        <span>{item.laneName}</span>
        <span>{timelineEntryTypeLabel(item.entry)}</span>
      </span>
    </Link>
  );
}

export function VerticalSpine({
  birthDate,
  model,
  referenceDate,
}: {
  birthDate: string | null;
  model: TimelineDisplayModel;
  referenceDate: string;
}) {
  const now = Date.parse(referenceDate);
  const firstFuture = model.dated.findIndex(
    (item) => Date.parse(item.entry.occurredStart ?? "") > now,
  );

  return (
    <>
      <section aria-label="Vertical timeline" className={styles.spine}>
        {birthDate ? (
          <div className={styles.anchor}>
            <span className={styles.anchorDot} aria-hidden="true" />
            <span>Birth · {birthDate.slice(0, 4)}</span>
          </div>
        ) : null}
        {model.dated.map((item, index) => (
          <div className={styles.entryBlock} key={item.entry.id}>
            {firstFuture === index ? (
              <div className={styles.anchor}>
                <span className={styles.anchorDot} aria-hidden="true" />
                <span>Today</span>
              </div>
            ) : null}
            <div
              className={`${styles.row} ${index % 2 ? styles.left : styles.right}`}
            >
              <span className={styles.node} aria-hidden="true" />
              <SpineCard item={item} />
            </div>
          </div>
        ))}
        {firstFuture === -1 ? (
          <div className={styles.anchor}>
            <span className={styles.anchorDot} aria-hidden="true" />
            <span>Today</span>
          </div>
        ) : null}
      </section>
      {model.undated.length ? (
        <section aria-labelledby="spine-undated" className={styles.undated}>
          <h2 id="spine-undated">Without a calendar date</h2>
          <p>These memories keep the date descriptions you recorded.</p>
          <div className={styles.undatedList}>
            {model.undated.map((item) => (
              <SpineCard item={item} key={item.entry.id} />
            ))}
          </div>
        </section>
      ) : null}
    </>
  );
}
