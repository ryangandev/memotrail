"use client";
import { useId, useState } from "react";
import { saveSemanticSearchPreference } from "@/app/settings/actions";
import { notify } from "@/components/app-toast";
import { SettingRow, settingRowIds } from "@/components/setting-row";
import { SettingSwitch } from "@/components/setting-switch";
import styles from "@/components/settings-fields.module.css";

export function SemanticSearchSetting({
  initialEnabled,
}: {
  initialEnabled: boolean;
}) {
  const id = useId();
  const ids = settingRowIds(id);
  const [enabled, setEnabled] = useState(initialEnabled);
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);

  async function change(next: boolean) {
    if (busy) return;
    const previous = enabled;
    setEnabled(next);
    setSaved(false);
    setBusy(true);

    try {
      const result = await saveSemanticSearchPreference(next);
      if (result.status === "saved") {
        setSaved(true);
      } else {
        setEnabled(previous);
        notify.error(result.message);
      }
    } catch {
      setEnabled(previous);
      notify.error(
        "MemoTrail could not save this setting. Check your connection and try again.",
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <SettingRow
      help="MemoTrail's own model reads your writing on MemoTrail's servers, and nothing is sent to an AI provider. Turning this off deletes the meaning index; keyword search always works."
      id={id}
      label="Search by meaning"
      saved={saved}
    >
      <div className={styles.switchControl}>
        <span>Find Entries from a description, not just exact words.</span>
        <SettingSwitch
          aria-describedby={ids.help}
          aria-labelledby={ids.label}
          checked={enabled}
          disabled={busy}
          onChange={(event) => void change(event.target.checked)}
        />
      </div>
    </SettingRow>
  );
}
