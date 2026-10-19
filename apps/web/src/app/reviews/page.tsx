import Link from "next/link";
import { EmptyState } from "@/components/empty-state";
import { PageFrame } from "@/components/page-frame";
import { PageHeader } from "@/components/page-header";
import { SectionHeader } from "@/components/section-header";
import { SeparatedList } from "@/components/separated-list";
import styles from "@/components/review-years.module.css";
import { entryRowDate } from "@/lib/data/entry-row";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { entryDisplayTitle, validTimezone } from "@/lib/data/occurrence";
import {
  loadChapterReviews,
  loadReviewYears,
  reviewToday,
} from "@/lib/data/reviews";

export const dynamic = "force-dynamic";

export const metadata = { title: "Reviews | MemoTrail" };

export default async function ReviewsPage() {
  const context = await getAuthenticatedContext();
  if (!context) return null;
  const { localDate, timezone } = await reviewToday();
  const [yearList, chapterList] = await Promise.all([
    loadReviewYears(context.client, localDate),
    loadChapterReviews(context.client),
  ]);
  const { years } = yearList;
  const { chapters } = chapterList;
  const made = new Intl.DateTimeFormat("en-US", {
    dateStyle: "medium",
    timeZone: timezone,
  });
  const nothing =
    !yearList.failed &&
    !chapterList.failed &&
    years.length === 0 &&
    chapters.length === 0;

  return (
    <PageFrame width="list">
      <PageHeader title={<>Reviews</>} />
      {nothing ? (
        <EmptyState
          description="A year appears here once it has ended with at least 5 dated Entries, and a Chapter once you make its review from its page."
          title="No reviews yet"
        />
      ) : (
        <div className={styles.index}>
          <section aria-labelledby="reviews-years">
            <SectionHeader headingId="reviews-years" title="Years" />
            {yearList.failed ? (
              <p className={styles.note} role="alert">
                Years could not load. Refresh to try again.
              </p>
            ) : years.length === 0 ? (
              <p className={styles.note}>
                A year appears here once it has ended with at least 5 dated
                Entries.
              </p>
            ) : (
              <ul aria-label="Years" className={styles.rows}>
                {years.map((year) => (
                  <li key={year.year}>
                    <Link className={styles.row} href={`/reviews/${year.year}`}>
                      <span className={styles.name}>{year.year}</span>
                      <SeparatedList className={styles.facts}>
                        <span>
                          {year.entryCount}{" "}
                          {year.entryCount === 1 ? "Entry" : "Entries"}
                        </span>
                        {year.reviewGeneratedAt ? (
                          <span>
                            Review made{" "}
                            {made.format(new Date(year.reviewGeneratedAt))}
                          </span>
                        ) : null}
                      </SeparatedList>
                    </Link>
                  </li>
                ))}
              </ul>
            )}
          </section>
          <section aria-labelledby="reviews-chapters">
            <SectionHeader headingId="reviews-chapters" title="Chapters" />
            {chapterList.failed ? (
              <p className={styles.note} role="alert">
                Chapter reviews could not load. Refresh to try again.
              </p>
            ) : chapters.length === 0 ? (
              <p className={styles.note}>
                A Chapter appears here once you make its review from its page.
              </p>
            ) : (
              <ul aria-label="Chapters" className={styles.rows}>
                {chapters.map(({ chapter, generatedAt }) => {
                  const occurrence = {
                    occurredAt: chapter.occurredStart,
                    occurredEnd: chapter.occurredEnd,
                    occurredLabel: chapter.occurredLabel,
                    occurredTimezone: validTimezone(chapter.occurredTimezone)
                      ? chapter.occurredTimezone
                      : "UTC",
                    datePrecision: chapter.datePrecision,
                  };
                  return (
                    <li key={chapter.id}>
                      <Link
                        className={styles.row}
                        href={`/items/${chapter.id}`}
                      >
                        <span className={styles.name}>
                          {chapter.title
                            ? entryDisplayTitle(chapter.title, occurrence)
                            : "Untitled Chapter"}
                        </span>
                        <SeparatedList className={styles.facts}>
                          <span>
                            {entryRowDate(occurrence, { isChapter: true })}
                          </span>
                          <span>
                            Review made {made.format(new Date(generatedAt))}
                          </span>
                        </SeparatedList>
                      </Link>
                    </li>
                  );
                })}
              </ul>
            )}
          </section>
        </div>
      )}
    </PageFrame>
  );
}
