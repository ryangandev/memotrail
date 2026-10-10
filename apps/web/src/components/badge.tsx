import type { ComponentPropsWithoutRef, ReactNode } from "react";
import {
  badgeDefaults,
  type BadgeSize,
  type BadgeTone,
} from "@/generated/design-system";
import styles from "./badge.module.css";

type BadgeProps = Omit<ComponentPropsWithoutRef<"span">, "children"> & {
  children: ReactNode;
  size?: BadgeSize;
  tone?: BadgeTone;
  uppercase?: boolean;
};

/**
 * A noninteractive, single-line label. Long text truncates within its container.
 * Specified in packages/design-system/components/badge.yaml.
 */
export function Badge({
  children,
  className,
  size = badgeDefaults.size,
  tone = badgeDefaults.tone,
  uppercase = badgeDefaults.uppercase,
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
