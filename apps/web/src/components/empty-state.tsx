import type { ReactNode } from "react";
import styles from "./empty-state.module.css";

export function EmptyState({
  title,
  description,
  icon,
  actions,
  headingLevel = 2,
  onClick,
}: {
  title: ReactNode;
  description?: ReactNode;
  icon?: ReactNode;
  actions?: ReactNode;
  headingLevel?: 2 | 3;
  onClick?: () => void;
}) {
  const Heading = onClick ? "strong" : headingLevel === 2 ? "h2" : "h3";
  const Root = onClick ? "button" : "div";
  return (
    <Root
      data-ui-empty-state
      className={styles.state}
      onClick={onClick}
      type={onClick ? "button" : undefined}
    >
      {icon ? (
        <span aria-hidden="true" className={styles.icon}>
          {icon}
        </span>
      ) : null}
      <Heading className={styles.title}>{title}</Heading>
      {description ? (
        <div className={styles.description}>{description}</div>
      ) : null}
      {actions ? <div className={styles.actions}>{actions}</div> : null}
    </Root>
  );
}
