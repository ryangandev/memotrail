import { useId } from "react";
import styles from "./segmented-control.module.css";

export type SegmentedOption<Value extends string> = {
  label: string;
  value: Value;
};

/**
 * One choice among two to four short options, drawn as a subtle track with the selected segment
 * raised. It is a fieldset of radio inputs, so the arrow keys move the selection.
 * Specified in packages/design-system/components/segmented-control.yaml.
 */
export function SegmentedControl<Value extends string>({
  className,
  disabled = false,
  label,
  name,
  onChange,
  options,
  value,
}: {
  className?: string;
  disabled?: boolean;
  /** Names the choice for assistive technology; the setting's visible label sits beside it. */
  label: string;
  /** The radio group's name; one is made up when omitted. */
  name?: string;
  onChange: (value: Value) => void;
  options: readonly SegmentedOption<Value>[];
  value: Value;
}) {
  const fallbackName = useId();
  return (
    <fieldset
      className={[styles.control, className].filter(Boolean).join(" ")}
      data-ui-segmented-control
      disabled={disabled}
    >
      <legend>{label}</legend>
      {options.map((option) => (
        <label key={option.value}>
          <input
            checked={value === option.value}
            name={name ?? fallbackName}
            onChange={() => onChange(option.value)}
            type="radio"
            value={option.value}
          />
          <span>{option.label}</span>
        </label>
      ))}
    </fieldset>
  );
}
