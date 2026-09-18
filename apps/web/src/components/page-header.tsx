import type { ReactNode } from "react";
import styles from "./page-header.module.css";

export function PageHeader({
  title,
  eyebrow,
  description,
  actions,
  headingLevel = 1,
}: {
  title: ReactNode;
  eyebrow?: ReactNode;
  description?: ReactNode;
  actions?: ReactNode;
  headingLevel?: 1 | 2;
}) {
  const Heading = headingLevel === 1 ? "h1" : "h2";
  return (
    <header data-ui-page-header className={styles.header}>
      <div className={styles.copy}>
        {eyebrow ? <p className={styles.eyebrow}>{eyebrow}</p> : null}
        <Heading className={styles.title}>{title}</Heading>
        {description ? (
          <div className={styles.description}>{description}</div>
        ) : null}
      </div>
      {actions ? <div className={styles.actions}>{actions}</div> : null}
    </header>
  );
}
