import Link from "next/link";
import type { TimelineIdeaModel } from "../_shared/model";
import { timelineIdeaEntryHref } from "../_shared/model";
import styles from "./vertical-spine.module.css";

export function VerticalSpine({
  birthDate,
  model,
  path,
}: {
  birthDate: string | null;
  model: TimelineIdeaModel;
  path: string;
}) {
  return (
    <>
      <div aria-label="Life timeline" className={styles.spine}>
        <div className={styles.anchor}>
          <span className={styles.anchorDot} aria-hidden="true" />
          <span>
            {birthDate
              ? `Birth · ${birthDate.slice(0, 4)}`
              : "The beginning of your timeline"}
          </span>
        </div>
        {model.dated.map((item, index) => (
          <div
            className={`${styles.row} ${index % 2 ? styles.left : styles.right}`}
            key={item.entry.id}
          >
            <span className={styles.node} aria-hidden="true" />
            <Link
              className={`${styles.card} ${item.entry.kind === "stage" ? styles.period : ""}`}
              href={timelineIdeaEntryHref(item.entry.id, path)}
            >
              <span className={styles.date}>{item.dateLabel}</span>
              <strong>{item.entry.title}</strong>
              {item.entry.body ? (
                <span className={styles.body}>{item.entry.body}</span>
              ) : null}
              <span className={styles.cardFooter}>
                <span>{item.trackName}</span>
                <span>{item.entry.kind === "stage" ? "Period" : "Moment"}</span>
              </span>
            </Link>
          </div>
        ))}
        <div className={styles.anchor}>
          <span className={styles.anchorDot} aria-hidden="true" />
          <span>Today</span>
        </div>
      </div>
      {model.undated.length ? (
        <section aria-labelledby="spine-undated" className={styles.undated}>
          <h2 id="spine-undated">Without a calendar date</h2>
          <p>These moments keep their own date descriptions.</p>
          <div className={styles.undatedList}>
            {model.undated.map((item) => (
              <Link
                href={timelineIdeaEntryHref(item.entry.id, path)}
                key={item.entry.id}
              >
                <span>{item.dateLabel}</span>
                <strong>{item.entry.title}</strong>
                <small>{item.trackName}</small>
              </Link>
            ))}
          </div>
        </section>
      ) : null}
    </>
  );
}
