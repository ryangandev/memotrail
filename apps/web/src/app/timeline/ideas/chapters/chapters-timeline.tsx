import Link from "next/link";
import type { TimelineIdeaItem, TimelineIdeaModel } from "../_shared/model";
import { timelineIdeaEntryHref } from "../_shared/model";
import styles from "./chapters-timeline.module.css";

function sections(model: TimelineIdeaModel) {
  const grouped = new Map<number, TimelineIdeaItem[]>();
  for (const item of model.dated) {
    if (item.year === null) continue;
    const decade = Math.floor(item.year / 10) * 10;
    const values = grouped.get(decade) ?? [];
    values.push(item);
    grouped.set(decade, values);
  }
  return [...grouped.entries()].sort(([a], [b]) => a - b);
}

function ChapterItem({ item, path }: { item: TimelineIdeaItem; path: string }) {
  return (
    <li>
      <Link href={timelineIdeaEntryHref(item.entry.id, path)}>
        <span className={styles.date}>{item.dateLabel}</span>
        <span className={styles.entryCopy}>
          <strong>{item.entry.title}</strong>
          {item.entry.body ? <span>{item.entry.body}</span> : null}
          <small>
            {item.trackName} ·{" "}
            {item.entry.kind === "stage" ? "Period" : "Moment"}
          </small>
        </span>
      </Link>
    </li>
  );
}

export function ChaptersTimeline({
  model,
  path,
}: {
  model: TimelineIdeaModel;
  path: string;
}) {
  const chapters = sections(model);
  return (
    <div className={styles.book}>
      <div className={styles.coverNote}>
        <span>MEMOTRAIL · A LIFE IN PROGRESS</span>
        <p>
          Each section gathers recorded moments by decade for reading. Periods
          retain their own dates and tracks.
        </p>
      </div>
      {chapters.map(([decade, items], index) => (
        <details className={styles.chapter} key={decade} open>
          <summary>
            <span className={styles.chapterNumber}>
              {String(index + 1).padStart(2, "0")}
            </span>
            <span className={styles.chapterTitle}>
              <small>Recorded years</small>
              <strong>The {decade}s</strong>
            </span>
            <span className={styles.chapterCount}>
              {items.length} {items.length === 1 ? "record" : "records"}
            </span>
          </summary>
          <ol>
            {items.map((item) => (
              <ChapterItem item={item} key={item.entry.id} path={path} />
            ))}
          </ol>
        </details>
      ))}
      {model.undated.length ? (
        <details className={styles.chapter} open>
          <summary>
            <span className={styles.chapterNumber}>··</span>
            <span className={styles.chapterTitle}>
              <small>Beyond the calendar</small>
              <strong>Unplaced pages</strong>
            </span>
            <span className={styles.chapterCount}>
              {model.undated.length} records
            </span>
          </summary>
          <ol>
            {model.undated.map((item) => (
              <ChapterItem item={item} key={item.entry.id} path={path} />
            ))}
          </ol>
        </details>
      ) : null}
    </div>
  );
}
