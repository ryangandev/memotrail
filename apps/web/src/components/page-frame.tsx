import type { HTMLAttributes, ReactNode } from "react";
import {
  pageFrameDefaults,
  type PageFrameVariant,
} from "@/generated/design-system";
import styles from "./page-frame.module.css";

/**
 * The centered column that holds a page, at most its variant's width and inset by the page
 * gutter. Specified in packages/design-system/components/page-frame.yaml.
 */
export function PageFrame({
  children,
  className,
  variant = pageFrameDefaults.variant,
  ...props
}: HTMLAttributes<HTMLDivElement> & {
  children: ReactNode;
  variant?: PageFrameVariant;
}) {
  return (
    <div
      {...props}
      className={[styles.frame, styles[variant], className]
        .filter(Boolean)
        .join(" ")}
      data-page-frame={variant}
      data-ui-page-frame
      data-variant={variant}
    >
      {children}
    </div>
  );
}
