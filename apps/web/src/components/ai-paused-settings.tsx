import { Badge } from "./badge";
import { Icon } from "./icon";
import { PageFrame } from "./page-frame";
import { PageHeader } from "./page-header";
import { AI_PAUSED_MESSAGE } from "@/lib/ai/availability";
import styles from "./ai-paused-settings.module.css";

export function AIPausedSettings() {
  return (
    <PageFrame className={styles.content} variant="compact">
      <PageHeader
        title={<>AI capabilities</>}
        eyebrow={<>Beta · Paused</>}
        description={<>{AI_PAUSED_MESSAGE}</>}
      />
      <section className={styles.primaryCard} aria-label="AI availability">
        <div className={styles.primaryHeading}>
          <span className={styles.primaryIcon}>
            <Icon name="sparkle" size={22} />
          </span>
          <div>
            <h2>AI capabilities</h2>
            <p>Currently off and unavailable to enable.</p>
          </div>
          <Badge className={styles.availability} tone="neutral">
            Beta
          </Badge>
        </div>
        <label className={styles.switchRow}>
          <span>
            <strong>AI capabilities</strong>
            <small>Capture, organize, and search your archive manually.</small>
          </span>
          <span className={styles.switchControl}>
            <input
              aria-label="AI capabilities"
              checked={false}
              disabled
              readOnly
              role="switch"
              type="checkbox"
            />
            <span aria-hidden="true" className={styles.switchTrack}>
              <span />
            </span>
          </span>
        </label>
        <p className={styles.unavailableNote}>
          No new AI requests will run while this beta is paused. Your Entries
          and previous AI data are preserved.
        </p>
      </section>
    </PageFrame>
  );
}
