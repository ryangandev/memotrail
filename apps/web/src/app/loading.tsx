import pageStyles from "@/app/page.module.css";
import { PageFrame } from "@/components/page-frame";
import { Skeleton } from "@/components/skeleton";

export default function Loading() {
  return (
    <PageFrame
      aria-label="Loading page"
      aria-live="polite"
      className={pageStyles.routeLoading}
      role="status"
      variant="wide"
    >
      <Skeleton height="11px" width="112px" />
      <Skeleton
        className={pageStyles.loadingTitle}
        height="42px"
        width="min(68%, 460px)"
      />
      <Skeleton
        className={pageStyles.loadingIntro}
        height="16px"
        width="min(82%, 620px)"
      />
      <div className={pageStyles.loadingCards}>
        <Skeleton height="auto" />
        <Skeleton height="auto" />
        <Skeleton height="auto" />
      </div>
      <span className={pageStyles.loadingLabel}>Loading your trail...</span>
    </PageFrame>
  );
}
