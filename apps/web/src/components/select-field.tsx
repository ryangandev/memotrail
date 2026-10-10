"use client";

import { useId, type ComponentProps, type ReactNode } from "react";
import { Icon } from "@/components/icon";
import {
  selectFieldDefaults,
  type SelectFieldSize,
} from "@/generated/design-system";
import styles from "./select-field.module.css";

export type SelectFieldProps = Omit<
  ComponentProps<"select">,
  "children" | "size"
> & {
  /** Option elements, grouped in titled optgroup elements where the list has groups. */
  children: ReactNode;
  hideLabel?: boolean;
  label: string;
  size?: SelectFieldSize;
};

/**
 * A labeled native select on the shared field surface.
 * Specified in packages/design-system/components/select-field.yaml.
 */
export function SelectField({
  children,
  className,
  disabled,
  hideLabel = selectFieldDefaults.hideLabel,
  id,
  label,
  required = selectFieldDefaults.required,
  size = selectFieldDefaults.size,
  ...selectProps
}: SelectFieldProps) {
  const generatedId = useId();

  return (
    <div
      className={[styles.field, className].filter(Boolean).join(" ")}
      data-disabled={disabled ? "true" : undefined}
      data-size={size}
      data-ui-field
      data-ui-select-field
    >
      <label
        className={styles.label}
        data-hidden={hideLabel ? "true" : undefined}
        htmlFor={id ?? generatedId}
      >
        {label}
        {required ? (
          <span aria-hidden="true" className={styles.requiredMark}>
            *
          </span>
        ) : null}
      </label>
      <div className={styles.control}>
        {/* data-ui-select opts out of the global select chevron; the Icon below draws this one. */}
        <select
          {...selectProps}
          data-ui-select
          disabled={disabled}
          id={id ?? generatedId}
          required={required}
        >
          {children}
        </select>
        <Icon name="chevron" size={15} />
      </div>
    </div>
  );
}
