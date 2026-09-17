import type { ReactNode } from "react";
import styles from "./record-card.module.css";

export function RecordCard({
  ariaLabel,
  children,
  className,
  onClick,
}: {
  ariaLabel: string;
  children: ReactNode;
  className?: string;
  onClick: () => void;
}) {
  return (
    <button
      aria-label={ariaLabel}
      className={classes(styles.card, className)}
      data-record-card="true"
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
