import type { ReactNode } from "react";
import styles from "./empty-state.module.css";

type EmptyStateAction =
  | { onClick: () => void; actions?: never }
  | { onClick?: undefined; actions?: ReactNode };

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
  headingLevel?: 2 | 3;
} & EmptyStateAction) {
  const Heading = onClick ? "strong" : headingLevel === 2 ? "h2" : "h3";
  const Root = onClick ? "button" : "div";
  const Description = onClick ? "span" : "div";
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
        <Description className={styles.description}>{description}</Description>
      ) : null}
      {actions ? <div className={styles.actions}>{actions}</div> : null}
    </Root>
  );
}
