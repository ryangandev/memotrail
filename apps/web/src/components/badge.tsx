import type { ComponentPropsWithoutRef, ReactNode } from "react";
import styles from "./badge.module.css";

type BadgeProps = Omit<ComponentPropsWithoutRef<"span">, "children"> & {
  children: ReactNode;
  size?: "micro" | "small" | "medium";
  tone?:
    | "accent"
    | "neutral"
    | "warm"
    | "outline"
    | "inverse"
    | "solidAccent"
    | "glassAccent"
    | "glassNeutral";
  uppercase?: boolean;
};

/** A noninteractive, single-line label. Long text truncates within its container. */
export function Badge({
  children,
  className,
  size = "small",
  tone = "accent",
  uppercase = false,
  ...props
}: BadgeProps) {
  return (
    <span
      {...props}
      className={[styles.badge, className].filter(Boolean).join(" ")}
      data-size={size}
      data-tone={tone}
      data-uppercase={uppercase || undefined}
      data-ui-badge
    >
      {children}
    </span>
  );
}
