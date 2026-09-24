import Link from "next/link";
import type { TimelineIdeaItem, TimelineIdeaModel } from "../_shared/model";
import { timelineIdeaEntryHref } from "../_shared/model";
import styles from "./minimal-index-timeline.module.css";

function IndexRow({ item, path }: { item: TimelineIdeaItem; path: string }) {
  return (
    <li>
      <Link href={timelineIdeaEntryHref(item.entry.id, path)}>
        <span className={styles.year}>
          {item.year ?? "?"}
          {item.entry.kind === "stage" ? <small>Period</small> : null}
        </span>
        <span className={styles.copy}>
          <strong>{item.entry.title}</strong>
          <span className={styles.date}>{item.dateLabel}</span>
          {item.entry.body ? (
            <span className={styles.body}>{item.entry.body}</span>
          ) : null}
          <small>{item.trackName}</small>
        </span>
        <span aria-hidden="true" className={styles.arrow}>
          ↗
        </span>
      </Link>
    </li>
  );
}

export function MinimalIndexTimeline({
  model,
  path,
}: {
  model: TimelineIdeaModel;
  path: string;
}) {
  return (
    <div className={styles.index}>
      <div className={styles.intro}>
        <span>THE RECORDED LIFE</span>
        <p>
          {model.items.length} moments and periods, arranged by what is known.
        </p>
      </div>
      <ol className={styles.rows}>
        {model.dated.map((item) => (
          <IndexRow item={item} key={item.entry.id} path={path} />
        ))}
      </ol>
      {model.undated.length ? (
        <section aria-labelledby="index-undated" className={styles.undated}>
          <h2 id="index-undated">Without a calendar date</h2>
          <ol className={styles.rows}>
            {model.undated.map((item) => (
              <IndexRow item={item} key={item.entry.id} path={path} />
            ))}
          </ol>
        </section>
      ) : null}
    </div>
  );
}
