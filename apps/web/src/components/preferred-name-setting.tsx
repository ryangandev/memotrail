"use client";

import { useRouter } from "next/navigation";
import { useId, useRef, useState, type FormEvent } from "react";
import { savePreferredName } from "@/app/settings/actions";
import { notify } from "@/components/app-toast";
import { SettingRow, settingRowIds } from "@/components/setting-row";
import { TextField } from "@/components/text-field";
import styles from "./settings-fields.module.css";

/** The name Dashboard greets the person by. It saves when the field loses focus or on Enter. */
export function PreferredNameSetting({
  initialName,
}: {
  initialName: string | null;
}) {
  const router = useRouter();
  const id = useId();
  const ids = settingRowIds(id);
  const [name, setName] = useState(initialName ?? "");
  const [savedName, setSavedName] = useState(initialName ?? "");
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);
  const saving = useRef(false);

  async function save() {
    if (saving.current || name === savedName) return;
    saving.current = true;
    setBusy(true);
    try {
      const result = await savePreferredName(name);
      if (result.status === "error") {
        notify.error(result.message);
        return;
      }
      const normalized = result.preferredName ?? "";
      setName(normalized);
      setSavedName(normalized);
      setSaved(true);
      router.refresh();
    } catch {
      notify.error("MemoTrail could not save your preferred name. Try again.");
    } finally {
      saving.current = false;
      setBusy(false);
    }
  }

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    void save();
  }

  return (
    <SettingRow
      help="Used in your Dashboard greeting. Leave blank to use your Google name."
      id={id}
      label="Preferred name"
      labelFor={`${id}-field`}
      saved={saved}
    >
      <form className={styles.field} onSubmit={submit}>
        <TextField
          aria-labelledby={ids.label}
          autoComplete="nickname"
          disabled={busy}
          hideLabel
          id={`${id}-field`}
          label="Preferred name"
          maxLength={80}
          onBlur={() => void save()}
          onChange={(event) => {
            setName(event.target.value);
            setSaved(false);
          }}
          value={name}
        />
      </form>
    </SettingRow>
  );
}
