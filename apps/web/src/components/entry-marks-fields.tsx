"use client";

import { Checkbox } from "@/components/checkbox";
import styles from "./entry-marks-fields.module.css";

export type EntryMarks = { isChapter: boolean; isFirstTime: boolean };

// The two marks any Entry can carry. A Chapter is a stretch of your life that appears on
// Timeline and gathers the Entries dated inside it; a First Time is the first time you did
// something. An Entry can carry both.
export function EntryMarksFields({
  disabled,
  onChange,
  value,
}: {
  disabled: boolean;
  onChange: (value: EntryMarks) => void;
  value: EntryMarks;
}) {
  return (
    <fieldset
      aria-label="Marks"
      className={styles.marks}
      data-ui-field
      disabled={disabled}
    >
      <Checkbox
        checked={value.isChapter}
        description="A stretch of your life, like a home, a job, or a school year."
        label="Chapter"
        onChange={(event) =>
          onChange({ ...value, isChapter: event.target.checked })
        }
      />
      <Checkbox
        checked={value.isFirstTime}
        description="The first time you did something."
        label="First Time"
        onChange={(event) =>
          onChange({ ...value, isFirstTime: event.target.checked })
        }
      />
    </fieldset>
  );
}
