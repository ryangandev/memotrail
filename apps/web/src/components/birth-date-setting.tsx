"use client";

import { useState, type FormEvent } from "react";
import { saveBirthDate } from "@/app/settings/actions";
import { PrecisionDateField } from "@/components/precision-date-field";
import styles from "@/app/settings/page.module.css";

export function BirthDateSetting({
  initialBirthDate,
  maxValue,
}: {
  initialBirthDate: string | null;
  maxValue: string;
}) {
  const [birthDate, setBirthDate] = useState(initialBirthDate ?? "");
  const [savedBirthDate, setSavedBirthDate] = useState(initialBirthDate ?? "");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy || birthDate === savedBirthDate) return;

    setBusy(true);
    setMessage(null);

    try {
      const result = await saveBirthDate(birthDate);
      setMessage(result.message);
      if (result.status === "saved") {
        setSavedBirthDate(result.birthDate ?? "");
      }
    } catch {
      setMessage("MemoTrail could not save your birth date. Try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className={styles.birthDateCard} onSubmit={submit}>
      <div>
        <strong>Timeline starting point</strong>
        <p>
          Your birth date stays private and lets Timeline show your story from
          its real beginning.
        </p>
      </div>
      <PrecisionDateField
        disabled={busy}
        label="Birth date"
        maxValue={maxValue}
        onChange={setBirthDate}
        precision="day"
        value={birthDate}
      />
      <div className={styles.birthDateControls}>
        <button disabled={busy || birthDate === savedBirthDate} type="submit">
          {busy ? "Saving…" : "Save birth date"}
        </button>
        {message ? <span role="status">{message}</span> : null}
      </div>
    </form>
  );
}
