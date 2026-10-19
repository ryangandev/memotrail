"use client";

import { useId, useState } from "react";
import { saveProfileTimezone } from "@/app/settings/actions";
import { notify } from "@/components/app-toast";
import { SettingRow } from "@/components/setting-row";
import { TimezoneSelect } from "@/components/timezone-select";
import styles from "./settings-fields.module.css";

/** The default time zone for new exact times. It saves as soon as a zone is chosen. */
export function TimezoneSetting({
  initialTimezone,
}: {
  initialTimezone: string;
}) {
  const id = useId();
  const [timezone, setTimezone] = useState(initialTimezone);
  const [savedTimezone, setSavedTimezone] = useState(initialTimezone);
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);

  async function change(next: string) {
    if (busy) return;
    setTimezone(next);
    setSaved(false);
    if (next === savedTimezone) return;
    setBusy(true);
    try {
      const result = await saveProfileTimezone(next);
      if (result.status === "saved" && result.timezone) {
        setSavedTimezone(result.timezone);
        setSaved(true);
      } else {
        setTimezone(savedTimezone);
        notify.error(result.message);
      }
    } catch {
      setTimezone(savedTimezone);
      notify.error(
        "MemoTrail could not save your default time zone. Try again.",
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <SettingRow
      help="Used for new exact times. Existing moments keep the time zone recorded with them."
      id={id}
      label="Default time zone"
      labelFor={`${id}-field`}
      saved={saved}
    >
      <TimezoneSelect
        ariaLabel="Default time zone"
        className={styles.select}
        disabled={busy}
        id={`${id}-field`}
        onChange={(event) => void change(event.target.value)}
        value={timezone}
      />
    </SettingRow>
  );
}
