import type { HTMLAttributes, ReactNode } from "react";
import {
  pageFrameDefaults,
  type PageFrameWidth,
} from "@/generated/design-system";
import styles from "./page-frame.module.css";

/**
 * The column that holds a page. It starts at the workspace's fixed left edge, so titles never
 * move sideways between pages, and is at most its width: reading is 720 px, list 960 px, and
 * full fills the workspace. Specified in packages/design-system/components/page-frame.yaml.
 */
export function PageFrame({
  children,
  className,
  width = pageFrameDefaults.width,
  ...props
}: HTMLAttributes<HTMLDivElement> & {
  children: ReactNode;
  width?: PageFrameWidth;
}) {
  return (
    <div
      {...props}
      className={[styles.frame, className].filter(Boolean).join(" ")}
      data-page-frame={width}
      data-ui-page-frame
      data-width={width}
    >
      {children}
    </div>
  );
}
