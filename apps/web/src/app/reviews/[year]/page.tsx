import { notFound } from "next/navigation";
import { ReviewPanel } from "@/components/review-panel";
import { PageFrame } from "@/components/page-frame";
import { PageHeader } from "@/components/page-header";
import styles from "@/components/review-years.module.css";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  loadReviewSettings,
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

export default async function YearReviewPage({ params }: YearReviewPageProps) {
  const { year: text } = await params;
  const context = await getAuthenticatedContext();
  if (!context) return null;
  const { localDate, timezone } = await reviewToday();
  const year = /^\d{4}$/.test(text) ? Number(text) : null;
  if (year === null || year < 1900 || year > Number(localDate.slice(0, 4)))
    notFound();

  const [data, preferences] = await Promise.all([
    loadYearReview(context.client, year, localDate),
    loadReviewSettings(context.client),
  ]);

  return (
    <PageFrame width="reading">
      <PageHeader
        back="reviews"
        meta={<>Year in review</>}
        title={<>{year}</>}
      />
      {!data || !preferences ? (
        <p role="alert">This year could not load. Refresh to try again.</p>
      ) : data.eligibility.status === "not_over" ? (
        <p className={styles.note}>
          This year is not over yet. Come back in January.
        </p>
      ) : data.eligibility.status === "too_few_entries" &&
        !data.review?.content ? (
        <p className={styles.note}>
          A year needs at least {data.eligibility.minimum} dated Entries for a
          review. {year} has {data.eligibility.entryCount}.
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
