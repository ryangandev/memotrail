import type { ComponentPropsWithoutRef, CSSProperties } from "react";
import styles from "./skeleton.module.css";

type SkeletonProps = Omit<
  ComponentPropsWithoutRef<"span">,
  "children" | "aria-hidden"
> & {
  /** `fill` takes its whole container, like a photo that is still arriving. */
  shape?: "fill" | "block" | "line" | "circle";
  /** Any CSS length. A circle uses `width` for both sides. */
  width?: CSSProperties["width"];
  height?: CSSProperties["height"];
  /** Stops the shimmer, for a placeholder that is about to be replaced. */
  animated?: boolean;
};

/**
 * A decorative placeholder for content that is still loading.
 * It is hidden from assistive technology, so the surrounding region announces the loading state.
 */
export function Skeleton({
  animated = true,
  className,
  height,
  shape = "block",
  style,
  width,
  ...props
}: SkeletonProps) {
  return (
    <span
      {...props}
      aria-hidden="true"
      className={[styles.skeleton, className].filter(Boolean).join(" ")}
      data-animated={animated}
      data-shape={shape}
      data-ui-skeleton
      style={{
        ...(width ? { width } : null),
        ...(height ? { height } : null),
        ...style,
      }}
    />
  );
}
