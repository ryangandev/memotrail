"use client";
import { notify } from "@/components/app-toast";
import settingsFieldsStyles from "@/components/settings-fields.module.css";
import { Button } from "@/components/button";

import { useState, type FormEvent } from "react";
import { saveProfileTimezone } from "@/app/settings/actions";
import { TimezoneSelect } from "@/components/timezone-select";

export function TimezoneSetting({
  initialTimezone,
}: {
  initialTimezone: string;
}) {
  const [timezone, setTimezone] = useState(initialTimezone);
  const [savedTimezone, setSavedTimezone] = useState(initialTimezone);
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy || timezone === savedTimezone) return;

    setBusy(true);

    try {
      const result = await saveProfileTimezone(timezone);
      if (result.status === "saved") notify.success(result.message);
      else notify.error(result.message);
      if (result.status === "saved" && result.timezone) {
        setSavedTimezone(result.timezone);
      }
    } catch {
      notify.error(
        "MemoTrail could not save your default time zone. Try again.",
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className={settingsFieldsStyles.timezoneCard} onSubmit={submit}>
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
      <div className={settingsFieldsStyles.timezoneControls}>
        <Button
          variant="primary"
          disabled={busy || timezone === savedTimezone}
          type="submit"
        >
          {busy ? "Saving..." : "Save time zone"}
        </Button>
      </div>
    </form>
  );
}
