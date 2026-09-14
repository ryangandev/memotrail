import { PageFrame } from "@/components/page-frame";
import styles from "./page.module.css";

export default function Loading() {
  return (
    <PageFrame
      aria-label="Loading page"
      aria-live="polite"
      className={styles.routeLoading}
      role="status"
      variant="wide"
    >
      <span className={styles.loadingEyebrow} />
      <span className={styles.loadingTitle} />
      <span className={styles.loadingIntro} />
      <div className={styles.loadingCards} aria-hidden="true">
        <span />
        <span />
        <span />
      </div>
      <span className={styles.loadingLabel}>Loading your trail...</span>
    </PageFrame>
  );
}
