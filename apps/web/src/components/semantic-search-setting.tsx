"use client";
import { useState } from "react";
import { saveSemanticSearchPreference } from "@/app/settings/actions";
import { notify } from "@/components/app-toast";
import { Checkbox } from "@/components/checkbox";
import settingsFieldsStyles from "@/components/settings-fields.module.css";

export function SemanticSearchSetting({
  initialEnabled,
}: {
  initialEnabled: boolean;
}) {
  const [enabled, setEnabled] = useState(initialEnabled);
  const [busy, setBusy] = useState(false);

  async function change(next: boolean) {
    if (busy) return;
    const previous = enabled;
    setEnabled(next);
    setBusy(true);

    try {
      const result = await saveSemanticSearchPreference(next);
      if (result.status === "saved") {
        notify.success(result.message);
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
    <div className={settingsFieldsStyles.semanticSearchCard}>
      <Checkbox
        checked={enabled}
        description="Find Entries from a description, not just exact words. MemoTrail's own model reads your writing on MemoTrail's servers, and nothing is sent to an AI provider. Turning this off deletes the meaning index; keyword search always works."
        disabled={busy}
        label="Search by meaning"
        onChange={(event) => void change(event.target.checked)}
      />
    </div>
  );
}
