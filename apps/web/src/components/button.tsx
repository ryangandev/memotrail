import Link from "next/link";
import type { ComponentProps, ReactNode } from "react";
import {
  buttonDefaults,
  type ButtonSize,
  type ButtonVariant,
} from "@/generated/design-system";
import styles from "./button.module.css";

type ButtonAppearance = {
  variant?: ButtonVariant;
  size?: ButtonSize;
};

export type ButtonProps = ComponentProps<"button"> &
  ButtonAppearance & { loading?: boolean };

/**
 * A labeled action. Loading shows a spinner, sets aria-busy, and disables the button.
 * Specified in packages/design-system/components/button.yaml.
 */
export function Button({
  children,
  className,
  disabled,
  loading = buttonDefaults.loading,
  size = buttonDefaults.size,
  type = "button",
  variant = buttonDefaults.variant,
  ...props
}: ButtonProps) {
  return (
    <button
      {...props}
      aria-busy={loading || props["aria-busy"]}
      className={[styles.button, className].filter(Boolean).join(" ")}
      data-size={size}
      data-ui-button
      data-variant={variant}
      disabled={disabled || loading}
      type={type}
    >
      {loading ? <span aria-hidden="true" className={styles.spinner} /> : null}
      {children}
    </button>
  );
}

export function IconButton({
  children,
  className,
  label,
  ...props
}: Omit<ButtonProps, "children" | "aria-label"> & {
  children: ReactNode;
  label: string;
}) {
  return (
    <Button
      {...props}
      aria-label={label}
      className={[styles.iconButton, className].filter(Boolean).join(" ")}
    >
      {props.loading ? null : children}
    </Button>
  );
}

// Navigation remains an anchor; it does not acquire button-only disabled/submit semantics.
export function ButtonLink({
  className,
  size = buttonDefaults.size,
  variant = buttonDefaults.variant,
  ...props
}: ComponentProps<typeof Link> & ButtonAppearance) {
  return (
    <Link
      {...props}
      className={[styles.button, className].filter(Boolean).join(" ")}
      data-size={size}
      data-ui-button
      data-variant={variant}
    />
  );
}
