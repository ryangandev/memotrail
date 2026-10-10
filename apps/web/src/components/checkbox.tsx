import { useId, type ComponentPropsWithoutRef, type ReactNode } from "react";
import { checkboxDefaults, type CheckboxSize } from "@/generated/design-system";
import { Icon } from "./icon";
import styles from "./checkbox.module.css";

export type CheckboxProps = Omit<
  ComponentPropsWithoutRef<"input">,
  "children" | "size" | "type"
> & {
  label: ReactNode;
  description?: ReactNode;
  size?: CheckboxSize;
};

/**
 * A native checkbox with a visible label and an optional explanation.
 * Props go to the input, so name, value, defaultChecked, and form behavior are unchanged;
 * `className` goes to the wrapper for placement.
 * Specified in packages/design-system/components/checkbox.yaml.
 */
export function Checkbox({
  "aria-describedby": describedBy,
  className,
  description,
  id,
  label,
  size = checkboxDefaults.size,
  ...inputProps
}: CheckboxProps) {
  const generatedId = useId();
  const inputId = id ?? generatedId;
  const labelId = `${inputId}-label`;
  const descriptionId = `${inputId}-description`;
  const described = [describedBy, description ? descriptionId : undefined]
    .filter(Boolean)
    .join(" ");

  return (
    <div
      className={[styles.checkbox, className].filter(Boolean).join(" ")}
      data-size={size}
      data-ui-checkbox
      data-ui-field
    >
      <label className={styles.control} htmlFor={inputId}>
        <input
          {...inputProps}
          aria-describedby={described || undefined}
          aria-labelledby={labelId}
          className={styles.input}
          id={inputId}
          type="checkbox"
        />
        <span aria-hidden="true" className={styles.box}>
          <Icon name="check" size={size === "small" ? 12 : 14} />
        </span>
        <span className={styles.text}>
          <span className={styles.label} id={labelId}>
            {label}
          </span>
          {description ? (
            <small className={styles.description} id={descriptionId}>
              {description}
            </small>
          ) : null}
        </span>
      </label>
    </div>
  );
}
