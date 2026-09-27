"use client";

import { useId, type ComponentProps } from "react";
import styles from "./text-field.module.css";

export type TextFieldProps = Omit<
  ComponentProps<"input">,
  "children" | "size" | "type"
> & {
  label: string;
  size?: "small" | "medium" | "large";
};

export function TextField({
  className,
  disabled,
  id,
  label,
  size = "medium",
  ...inputProps
}: TextFieldProps) {
  const generatedId = useId();
  const inputId = id ?? generatedId;

  return (
    <div
      className={[styles.field, className].filter(Boolean).join(" ")}
      data-disabled={disabled ? "true" : undefined}
      data-size={size}
      data-text-field
      data-ui-field
    >
      <label htmlFor={inputId}>{label}</label>
      <div className={styles.control}>
        <input {...inputProps} disabled={disabled} id={inputId} type="text" />
      </div>
    </div>
  );
}
