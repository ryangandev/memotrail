import type { ReactNode } from "react";
import styles from "./empty-state.module.css";

type EmptyStateAction =
  | { onClick: () => void; actions?: never }
  | { onClick?: undefined; actions?: ReactNode };

/**
 * What a place with nothing to show says, inline at the page's left edge: an optional quiet icon,
 * one sentence, an optional second line, and at most one next step. The same style serves every
 * empty list, search without matches, and missing page. Specified in
 * packages/design-system/components/empty-state.yaml.
 */
export function EmptyState({
  title,
  description,
  icon,
  actions,
  headingLevel = 2,
  onClick,
}: {
  /** The one sentence that says what will appear here. */
  title: ReactNode;
  /** An optional second sentence, such as why or what to do. */
  description?: ReactNode;
  icon?: ReactNode;
  headingLevel?: 2 | 3;
} & EmptyStateAction) {
  const Heading = onClick ? "strong" : headingLevel === 2 ? "h2" : "h3";
  const Root = onClick ? "button" : "div";
  const Copy = onClick ? "span" : "div";
  const Description = onClick ? "span" : "div";
  return (
    <Root
      data-ui-empty-state
      className={styles.state}
      data-icon={icon ? "true" : undefined}
      onClick={onClick}
      type={onClick ? "button" : undefined}
    >
      {icon ? (
        <span aria-hidden="true" className={styles.icon}>
          {icon}
        </span>
      ) : null}
      <Copy className={styles.copy}>
        <Heading className={styles.title}>{title}</Heading>
        {description ? (
          <Description className={styles.description}>
            {description}
          </Description>
        ) : null}
      </Copy>
      {actions ? <div className={styles.actions}>{actions}</div> : null}
    </Root>
  );
}
