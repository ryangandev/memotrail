import type { ComponentPropsWithoutRef } from "react";
import styles from "./setting-switch.module.css";

/**
 * An on or off setting drawn as a switch. It is a native checkbox underneath, so it keeps the
 * checkbox role, the keyboard behavior, and form behavior; the track and thumb only draw it.
 * Name it with `aria-labelledby` from the row's label.
 */
export function SettingSwitch({
  className,
  ...inputProps
}: Omit<ComponentPropsWithoutRef<"input">, "children" | "size" | "type">) {
  return (
    <span
      className={[styles.switch, className].filter(Boolean).join(" ")}
      data-setting-switch
    >
      <input {...inputProps} className={styles.input} type="checkbox" />
      <span aria-hidden="true" className={styles.track} />
    </span>
  );
}
