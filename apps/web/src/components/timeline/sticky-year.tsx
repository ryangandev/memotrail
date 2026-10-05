import { SeparatedList } from "@/components/separated-list";
import Link from "next/link";
import type {
  TimelineDisplayItem,
  TimelineDisplayModel,
} from "@/lib/data/timeline-presentation";
import {
  groupTimelineYears,
  timelineEntryTypeLabel,
} from "@/lib/data/timeline-presentation";
import { wikiEntryHref } from "@/lib/data/wiki-item";
import styles from "./sticky-year.module.css";

function FeedCard({ item }: { item: TimelineDisplayItem }) {
  return (
    <Link
      aria-label={`${item.entry.title}, ${item.dateLabel}, ${item.laneName}`}
      className={`${styles.card} ${item.entry.shape === "period" ? styles.period : ""}`}
      href={wikiEntryHref(item.entry)}
    >
      <SeparatedList className={styles.cardMeta}>
        <span className={styles.laneName}>{item.laneName}</span>
        <span>{item.dateLabel}</span>
      </SeparatedList>
      <strong>{item.entry.title}</strong>
      {item.entry.body ? (
        <span className={styles.body}>{item.entry.body}</span>
      ) : null}
      <span className={styles.cardBottom}>
        <span>{timelineEntryTypeLabel(item.entry)}</span>
      </span>
    </Link>
  );
}

export function StickyYear({ model }: { model: TimelineDisplayModel }) {
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
              <FeedCard item={item} key={item.entry.id} />
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
              <FeedCard item={item} key={item.entry.id} />
            ))}
          </div>
        </section>
      ) : null}
    </div>
  );
}
