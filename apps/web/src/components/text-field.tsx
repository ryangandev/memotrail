"use client";

import { useId, type ComponentProps } from "react";
import {
  textFieldDefaults,
  type TextFieldSize,
} from "@/generated/design-system";
import styles from "./text-field.module.css";

export type TextFieldProps = Omit<
  ComponentProps<"input">,
  "children" | "size" | "type"
> & {
  /** Why the value is invalid. Shows below the control and marks the field invalid. */
  error?: string;
  hideLabel?: boolean;
  label: string;
  size?: TextFieldSize;
};

/**
 * A labeled single-line text input with a required mark and an inline error.
 * Specified in packages/design-system/components/text-field.yaml.
 */
export function TextField({
  "aria-describedby": describedBy,
  className,
  disabled,
  error,
  hideLabel = textFieldDefaults.hideLabel,
  id,
  label,
  required = textFieldDefaults.required,
  size = textFieldDefaults.size,
  ...inputProps
}: TextFieldProps) {
  const generatedId = useId();
  const inputId = id ?? generatedId;
  const messageId = `${inputId}-message`;

  return (
    <div
      className={[styles.field, className].filter(Boolean).join(" ")}
      data-disabled={disabled ? "true" : undefined}
      data-invalid={error ? "true" : undefined}
      data-size={size}
      data-text-field
      data-ui-field
      data-ui-text-field
    >
      <label
        className={styles.label}
        data-hidden={hideLabel ? "true" : undefined}
        htmlFor={inputId}
      >
        {label}
        {required ? (
          <span aria-hidden="true" className={styles.requiredMark}>
            *
          </span>
        ) : null}
      </label>
      <div className={styles.control}>
        <input
          {...inputProps}
          aria-describedby={
            [describedBy, error ? messageId : null].filter(Boolean).join(" ") ||
            undefined
          }
          aria-invalid={error ? true : inputProps["aria-invalid"]}
          disabled={disabled}
          id={inputId}
          required={required}
          type="text"
        />
      </div>
      {error ? (
        <p className={styles.message} id={messageId}>
          {error}
        </p>
      ) : null}
    </div>
  );
}
