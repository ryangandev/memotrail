"use client";

import { useId, type ComponentProps, type ReactNode } from "react";
import { Icon } from "@/components/icon";
import {
  searchFieldDefaults,
  type SearchFieldSize,
} from "@/generated/design-system";
import styles from "./search-field.module.css";

export type SearchFieldProps = Omit<
  ComponentProps<"input">,
  "children" | "size" | "type"
> & {
  hideLabel?: boolean;
  label: string;
  size?: SearchFieldSize;
  trailing?: ReactNode;
};

/**
 * A labeled search input with one focus surface for its icon, query, and trailing content.
 * Specified in packages/design-system/components/search-field.yaml.
 */
export function SearchField({
  autoComplete = "off",
  className,
  disabled,
  hideLabel = searchFieldDefaults.hideLabel,
  id,
  label,
  size = searchFieldDefaults.size,
  trailing,
  ...inputProps
}: SearchFieldProps) {
  const generatedId = useId();
  const inputId = id ?? generatedId;

  return (
    <div
      className={[styles.field, className].filter(Boolean).join(" ")}
      data-disabled={disabled ? "true" : undefined}
      data-search-field
      data-size={size}
      data-ui-field
      data-ui-search-field
    >
      <label
        className={styles.label}
        data-hidden={hideLabel ? "true" : undefined}
        htmlFor={inputId}
      >
        {label}
      </label>
      <div className={styles.control} data-search-control>
        <Icon name="search" size={size === "small" ? 15 : 17} />
        <input
          {...inputProps}
          autoComplete={autoComplete}
          disabled={disabled}
          id={inputId}
          type="search"
        />
        {trailing ? <span className={styles.trailing}>{trailing}</span> : null}
      </div>
    </div>
  );
}
