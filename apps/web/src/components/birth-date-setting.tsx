"use client";

import { useId, useState } from "react";
import { saveBirthDate } from "@/app/settings/actions";
import { notify } from "@/components/app-toast";
import { DatePickerField } from "@/components/date-picker-field";
import { SettingRow } from "@/components/setting-row";
import styles from "./settings-fields.module.css";

const completeDate = /^\d{4}-\d{2}-\d{2}$/;

/**
 * The private birth date Timeline starts from. It saves as soon as the date is complete, or
 * cleared, whether it was picked or typed.
 */
export function BirthDateSetting({
  initialBirthDate,
  maxValue,
}: {
  initialBirthDate: string | null;
  maxValue: string;
}) {
  const id = useId();
  const [birthDate, setBirthDate] = useState(initialBirthDate ?? "");
  const [savedBirthDate, setSavedBirthDate] = useState(initialBirthDate ?? "");
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);

  async function save(next: string) {
    if (busy || next === savedBirthDate) return;
    setBusy(true);
    try {
      const result = await saveBirthDate(next);
      if (result.status === "saved") {
        setSavedBirthDate(result.birthDate ?? "");
        setSaved(true);
      } else {
        notify.error(result.message);
      }
    } catch {
      notify.error("MemoTrail could not save your birth date. Try again.");
    } finally {
      setBusy(false);
    }
  }

  function change(next: string) {
    setBirthDate(next);
    setSaved(false);
    if (next === "" || completeDate.test(next)) void save(next);
  }

  return (
    <SettingRow
      help="Stays private. Timeline starts from this date."
      id={id}
      label="Birth date"
      saved={saved}
    >
      <div className={styles.field}>
        <DatePickerField
          disabled={busy}
          granularity="day"
          hideLabel
          initialView="year"
          label="Birth date"
          maxValue={maxValue}
          onChange={change}
          size="medium"
          value={birthDate}
        />
      </div>
    </SettingRow>
  );
}
