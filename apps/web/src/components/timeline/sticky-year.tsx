import type { TimelineEntry } from "@/lib/data/timeline";
import type {
  TimelineDisplayItem,
  TimelineDisplayModel,
} from "@/lib/data/timeline-presentation";
import {
  groupTimelineYears,
  timelineEntryTypeLabel,
} from "@/lib/data/timeline-presentation";
import styles from "./sticky-year.module.css";

function FeedCard({
  item,
  onSelect,
}: {
  item: TimelineDisplayItem;
  onSelect: (entry: TimelineEntry) => void;
}) {
  return (
    <button
      aria-label={`${item.entry.title}, ${item.dateLabel}, ${item.trackName}`}
      className={`${styles.card} ${item.entry.kind === "stage" ? styles.period : ""}`}
      onClick={() => onSelect(item.entry)}
      type="button"
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
        <span>{timelineEntryTypeLabel(item.entry)}</span>
        {item.entry.collectionNames.slice(0, 2).map((name) => (
          <span key={name}>{name}</span>
        ))}
      </span>
    </button>
  );
}

export function StickyYear({
  model,
  onSelect,
}: {
  model: TimelineDisplayModel;
  onSelect: (entry: TimelineEntry) => void;
}) {
  return (
    <div aria-label="Timeline by year" className={styles.feed} role="region">
      {groupTimelineYears(model).map(([year, items]) => (
        <section
          aria-labelledby={`timeline-year-${year}`}
          className={styles.yearGroup}
          key={year}
        >
          <div className={styles.yearRail}>
            <h2 id={`timeline-year-${year}`}>{year}</h2>
            <span>
              {items.length} {items.length === 1 ? "record" : "records"}
            </span>
          </div>
          <div className={styles.cards}>
            {items.map((item) => (
              <FeedCard item={item} key={item.entry.id} onSelect={onSelect} />
            ))}
          </div>
        </section>
      ))}
      {model.undated.length ? (
        <section
          aria-labelledby="timeline-year-undated"
          className={styles.yearGroup}
        >
          <div className={styles.yearRail}>
            <h2 id="timeline-year-undated">Unplaced</h2>
            <span>No calendar anchor</span>
          </div>
          <div className={styles.cards}>
            {model.undated.map((item) => (
              <FeedCard item={item} key={item.entry.id} onSelect={onSelect} />
            ))}
          </div>
        </section>
      ) : null}
    </div>
  );
}
