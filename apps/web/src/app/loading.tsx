import pageStyles from "@/app/page.module.css";
import { PageFrame } from "@/components/page-frame";

export default function Loading() {
  return (
    <PageFrame
      aria-label="Loading page"
      aria-live="polite"
      className={pageStyles.routeLoading}
      role="status"
      variant="wide"
    >
      <span className={pageStyles.loadingEyebrow} />
      <span className={pageStyles.loadingTitle} />
      <span className={pageStyles.loadingIntro} />
      <div className={pageStyles.loadingCards} aria-hidden="true">
        <span />
        <span />
        <span />
      </div>
      <span className={pageStyles.loadingLabel}>Loading your trail...</span>
    </PageFrame>
  );
}
