import type { HTMLAttributes, ReactNode } from "react";
import styles from "./page-frame.module.css";

export const pageFrameVariants = [
  "compact",
  "standard",
  "wide",
  "canvas",
] as const;

export type PageFrameVariant = (typeof pageFrameVariants)[number];

export function PageFrame({
  children,
  className,
  variant = "standard",
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
    >
      {children}
    </div>
  );
}
