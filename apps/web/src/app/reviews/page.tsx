import Link from "next/link";
import { EmptyState } from "@/components/empty-state";
import { PageFrame } from "@/components/page-frame";
import { PageHeader } from "@/components/page-header";
import { SeparatedList } from "@/components/separated-list";
import styles from "@/components/review-years.module.css";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { loadReviewYears, reviewToday } from "@/lib/data/reviews";

export const dynamic = "force-dynamic";

export const metadata = { title: "Year reviews | MemoTrail" };

export default async function YearReviewsPage() {
  const context = await getAuthenticatedContext();
  if (!context) return null;
  const { localDate, timezone } = await reviewToday();
  const { years, failed } = await loadReviewYears(context.client, localDate);
  const made = new Intl.DateTimeFormat("en-US", {
    dateStyle: "medium",
    timeZone: timezone,
  });

  return (
    <PageFrame width="list">
      <PageHeader title={<>Year reviews</>} />
      {failed ? (
        <p role="alert">Year reviews could not load. Refresh to try again.</p>
      ) : years.length === 0 ? (
        <EmptyState
          description="Year reviews appear here once a year with at least 5 dated Entries has ended."
          title="No year reviews yet"
        />
      ) : (
        <ul aria-label="Years" className={styles.years}>
          {years.map((year) => (
            <li key={year.year}>
              <Link href={`/reviews/${year.year}`}>
                <strong>{year.year}</strong>
                <SeparatedList>
                  <span>{year.entryCount} Entries</span>
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
    </PageFrame>
  );
}
