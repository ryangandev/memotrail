import { Children, isValidElement, type ComponentPropsWithoutRef } from "react";
import styles from "./separated-list.module.css";

type SeparatedListProps = ComponentPropsWithoutRef<"span"> & {
  /** Lines start at the inline start, or end flush with the inline end. */
  align?: "start" | "end";
  /**
   * The default gap leaves room for focus rings. Word spacing reads like a
   * sentence, so keep it for plain text without links or buttons.
   */
  spacing?: "default" | "word";
};

/**
 * A wrapping row of short facts with a "·" between neighbors on the same line.
 * No line starts or ends with a separator, and assistive technology reads only
 * the facts. Set `--separated-list-gap`, `--separated-list-row-gap`, and
 * `--separated-list-separator-color` on `className` to adjust it further.
 */
export function SeparatedList({
  align = "start",
  children,
  className,
  spacing = "default",
  ...props
}: SeparatedListProps) {
  const items = Children.toArray(children);
  const separator = (
    <span aria-hidden="true" className={styles.separator}>
      ·
    </span>
  );
  return (
    <span
      {...props}
      className={[styles.list, className].filter(Boolean).join(" ")}
      data-align={align}
      data-spacing={spacing}
      data-ui-separated-list
    >
      <span className={styles.row}>
        {items.map((child, index) => (
          <span
            className={styles.item}
            key={
              isValidElement(child) && child.key !== null ? child.key : index
            }
          >
            {align === "start" && index > 0 ? separator : null}
            {child}
            {align === "end" && index < items.length - 1 ? separator : null}
          </span>
        ))}
      </span>
    </span>
  );
}
