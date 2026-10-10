import type { ReactNode } from "react";
import styles from "./record-card.module.css";

/**
 * The clickable card that opens one record: a media band on top, then the record's own body.
 * Specified in packages/design-system/components/record-card.yaml.
 */
export function RecordCard({
  ariaLabel,
  children,
  className,
  onClick,
}: {
  ariaLabel?: string;
  children: ReactNode;
  className?: string;
  onClick: () => void;
}) {
  return (
    <button
      aria-label={ariaLabel}
      className={classes(styles.card, className)}
      data-record-card="true"
      data-ui-record-card
      onClick={onClick}
      type="button"
    >
      {children}
    </button>
  );
}

export function RecordCardVisual({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return <div className={classes(styles.visual, className)}>{children}</div>;
}

export function RecordCardBody({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return <div className={classes(styles.body, className)}>{children}</div>;
}

function classes(...values: Array<string | undefined>) {
  return values.filter(Boolean).join(" ");
}
