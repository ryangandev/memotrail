"use client";
import { Button } from "@/components/button";

import { useState, type FormEvent } from "react";
import { saveProfileTimezone } from "@/app/settings/actions";
import { TimezoneSelect } from "@/components/timezone-select";
import styles from "@/app/settings/page.module.css";

export function TimezoneSetting({
  initialTimezone,
}: {
  initialTimezone: string;
}) {
  const [timezone, setTimezone] = useState(initialTimezone);
  const [savedTimezone, setSavedTimezone] = useState(initialTimezone);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy || timezone === savedTimezone) return;

    setBusy(true);
    setMessage(null);

    try {
      const result = await saveProfileTimezone(timezone);
      setMessage(result.message);
      if (result.status === "saved" && result.timezone) {
        setSavedTimezone(result.timezone);
      }
    } catch {
      setMessage("MemoTrail could not save your default time zone. Try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className={styles.timezoneCard} onSubmit={submit}>
      <div>
        <strong>Default time zone</strong>
        <p>
          Used for new exact times. Existing moments keep the time zone recorded
          with them.
        </p>
      </div>
      <label>
        <span>Time zone</span>
        <TimezoneSelect
          ariaLabel="Default time zone"
          disabled={busy}
          onChange={(event) => setTimezone(event.target.value)}
          value={timezone}
        />
      </label>
      <div className={styles.timezoneControls}>
        <Button
          variant="primary"
          disabled={busy || timezone === savedTimezone}
          type="submit"
        >
          {busy ? "Saving..." : "Save time zone"}
        </Button>
        {message ? <span role="status">{message}</span> : null}
      </div>
    </form>
  );
}
