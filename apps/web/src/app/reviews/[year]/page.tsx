import Link from "next/link";
import { notFound } from "next/navigation";
import { ReviewMeta, ReviewPanel } from "@/components/review-panel";
import { PageFrame } from "@/components/page-frame";
import { PageHeader } from "@/components/page-header";
import styles from "@/components/review-years.module.css";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  loadReviewSettings,
  loadReviewYears,
  loadYearReview,
  reviewToday,
} from "@/lib/data/reviews";

export const dynamic = "force-dynamic";

type YearReviewPageProps = { params: Promise<{ year: string }> };

export async function generateMetadata({ params }: YearReviewPageProps) {
  const { year } = await params;
  return {
    title: `${/^\d{4}$/.test(year) ? year : "Year"} in review | MemoTrail`,
  };
}

const entries = (count: number) =>
  `${count} ${count === 1 ? "Entry" : "Entries"}`;

export default async function YearReviewPage({ params }: YearReviewPageProps) {
  const { year: text } = await params;
  const context = await getAuthenticatedContext();
  if (!context) return null;
  const { localDate, timezone } = await reviewToday();
  const year = /^\d{4}$/.test(text) ? Number(text) : null;
  if (year === null || year < 1900 || year > Number(localDate.slice(0, 4)))
    notFound();

  const [data, preferences, { years }] = await Promise.all([
    loadYearReview(context.client, year, localDate),
    loadReviewSettings(context.client),
    loadReviewYears(context.client, localDate),
  ]);

  // Every year with a review to read or make, and this one, oldest first.
  const switcher = [...new Set([...years.map((row) => row.year), year])].sort(
    (a, b) => a - b,
  );
  const review = data?.review?.content ? data.review : null;
  const meta = review ? (
    <ReviewMeta
      chapterCount={data?.facts?.chapters.length ?? 0}
      review={review}
      timezone={timezone}
    />
  ) : data && data.eligibility.entryCount > 0 ? (
    entries(data.eligibility.entryCount)
  ) : null;

  return (
    <PageFrame width="reading">
      <PageHeader back="reviews" meta={meta} title={<>{year} in review</>} />
      {switcher.length > 1 ? (
        <nav aria-label="Year" className={styles.switcher}>
          {switcher.map((option) => (
            <Link
              aria-current={option === year ? "page" : undefined}
              href={`/reviews/${option}`}
              key={option}
            >
              {option}
            </Link>
          ))}
        </nav>
      ) : null}
      {!data || !preferences ? (
        <p className={styles.note} role="alert">
          This year could not load. Refresh to try again.
        </p>
      ) : data.eligibility.status === "not_over" ? (
        <p className={styles.note}>
          {year} is not over yet. Its review can be made in January.
        </p>
      ) : data.eligibility.status === "too_few_entries" &&
        !data.review?.content ? (
        <p className={styles.note}>
          {year} has {entries(data.eligibility.entryCount)} with a date. A
          review needs at least {data.eligibility.minimum}.
        </p>
      ) : (
        <ReviewPanel
          data={data}
          preferences={preferences}
          subject={{ scope: "year", year }}
          timezone={timezone}
          today={localDate}
        />
      )}
    </PageFrame>
  );
}
