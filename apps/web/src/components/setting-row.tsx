import type { ReactNode } from "react";
import styles from "./setting-row.module.css";

/** The ids a setting row shares with its control: the label, and the help line under it. */
export function settingRowIds(id: string) {
  return { help: `${id}-help`, label: `${id}-label` };
}

/**
 * One setting: its label on the left, its control on the right, an optional help line under the
 * control, and an inline "Saved" beside the control once the change has reached MemoTrail.
 * Pass `labelFor` when the control is a single field, so clicking the label focuses it.
 */
export function SettingRow({
  children,
  help,
  id,
  label,
  labelFor,
  saved,
}: {
  children: ReactNode;
  help?: ReactNode;
  /** A base id from useId; the label and help ids derive from it. */
  id: string;
  label: ReactNode;
  labelFor?: string;
  /** Show the inline "Saved". Omit for a setting that never saves a field, such as a link. */
  saved?: boolean;
}) {
  const ids = settingRowIds(id);
  const Label = labelFor ? "label" : "span";
  return (
    <div className={styles.row} data-setting-row>
      <Label className={styles.label} htmlFor={labelFor} id={ids.label}>
        {label}
      </Label>
      <div className={styles.control}>
        {children}
        {saved === undefined ? null : (
          <span className={styles.saved} role="status">
            {saved ? "Saved" : ""}
          </span>
        )}
      </div>
      {help ? (
        <p className={styles.help} id={ids.help}>
          {help}
        </p>
      ) : null}
    </div>
  );
}
