import Link from "next/link";
import type { TimelineIdeaItem, TimelineIdeaModel } from "../_shared/model";
import { timelineIdeaEntryHref } from "../_shared/model";
import styles from "./sticky-year-timeline.module.css";

function yearGroups(model: TimelineIdeaModel) {
  const groups = new Map<number, TimelineIdeaItem[]>();
  for (const item of model.dated) {
    if (item.year === null) continue;
    const values = groups.get(item.year) ?? [];
    values.push(item);
    groups.set(item.year, values);
  }
  return [...groups.entries()].sort(([a], [b]) => a - b);
}

function FeedCard({ item, path }: { item: TimelineIdeaItem; path: string }) {
  return (
    <Link
      className={`${styles.card} ${item.entry.kind === "stage" ? styles.period : ""}`}
      href={timelineIdeaEntryHref(item.entry.id, path)}
    >
      <span className={styles.cardMeta}>
        <span>{item.trackName}</span>
        <span aria-hidden="true">·</span>
        <span>{item.dateLabel}</span>
      </span>
      <strong>{item.entry.title}</strong>
      {item.entry.body ? (
        <span className={styles.body}>{item.entry.body}</span>
      ) : null}
      <span className={styles.cardBottom}>
        <span>{item.entry.kind === "stage" ? "Period" : "Moment"}</span>
        {item.entry.collectionNames.slice(0, 2).map((name) => (
          <span key={name}>{name}</span>
        ))}
      </span>
    </Link>
  );
}

export function StickyYearTimeline({
  model,
  path,
}: {
  model: TimelineIdeaModel;
  path: string;
}) {
  return (
    <div className={styles.feed}>
      {yearGroups(model).map(([year, items]) => (
        <section
          aria-labelledby={`year-${year}`}
          className={styles.yearGroup}
          key={year}
        >
          <div className={styles.yearRail}>
            <h2 id={`year-${year}`}>{year}</h2>
            <span>
              {items.length} {items.length === 1 ? "record" : "records"}
            </span>
          </div>
          <div className={styles.cards}>
            {items.map((item) => (
              <FeedCard item={item} key={item.entry.id} path={path} />
            ))}
          </div>
        </section>
      ))}
      {model.undated.length ? (
        <section aria-labelledby="year-undated" className={styles.yearGroup}>
          <div className={styles.yearRail}>
            <h2 id="year-undated">Unplaced</h2>
            <span>No calendar anchor</span>
          </div>
          <div className={styles.cards}>
            {model.undated.map((item) => (
              <FeedCard item={item} key={item.entry.id} path={path} />
            ))}
          </div>
        </section>
      ) : null}
    </div>
  );
}
