"use client";

import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { savePreferredName } from "@/app/settings/actions";
import { notify } from "@/components/app-toast";
import { Button } from "@/components/button";
import styles from "./settings-fields.module.css";

export function PreferredNameSetting({
  initialName,
}: {
  initialName: string | null;
}) {
  const router = useRouter();
  const [name, setName] = useState(initialName ?? "");
  const [savedName, setSavedName] = useState(initialName ?? "");
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy || name === savedName) return;
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
      notify.success(result.message);
      router.refresh();
    } catch {
      notify.error("MemoTrail could not save your preferred name. Try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className={styles.preferredNameCard} onSubmit={submit}>
      <div>
        <strong>What should we call you?</strong>
        <p>Used in your Home greeting. Leave blank to use your Google name.</p>
      </div>
      <label>
        <span>Preferred name</span>
        <input
          autoComplete="nickname"
          disabled={busy}
          maxLength={80}
          onChange={(event) => setName(event.target.value)}
          type="text"
          value={name}
        />
      </label>
      <div className={styles.preferredNameControls}>
        <Button disabled={busy || name === savedName} type="submit">
          {busy ? "Saving..." : "Save name"}
        </Button>
      </div>
    </form>
  );
}
