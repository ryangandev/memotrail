"use client";

import { useId, type ComponentProps, type ReactNode } from "react";
import { Icon } from "@/components/icon";
import styles from "./select-field.module.css";

export type SelectFieldProps = Omit<
  ComponentProps<"select">,
  "children" | "size"
> & {
  children: ReactNode;
  label: string;
  size?: "small" | "medium" | "large";
};

export function SelectField({
  children,
  className,
  disabled,
  id,
  label,
  size = "medium",
  ...selectProps
}: SelectFieldProps) {
  const generatedId = useId();

  return (
    <div
      className={[styles.field, className].filter(Boolean).join(" ")}
      data-disabled={disabled ? "true" : undefined}
      data-size={size}
      data-ui-field
    >
      <label htmlFor={id ?? generatedId}>{label}</label>
      <div className={styles.control}>
        {/* data-ui-select opts out of the global select chevron; the Icon below draws this one. */}
        <select
          {...selectProps}
          data-ui-select
          disabled={disabled}
          id={id ?? generatedId}
        >
          {children}
        </select>
        <Icon name="chevron" size={15} />
      </div>
    </div>
  );
}
