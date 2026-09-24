"use client";
import { Button } from "@/components/button";
import { useEffect, useState } from "react";
import Link from "next/link";
import { dismissAISuggestion } from "@/app/settings/ai/actions";
import type {
  EntryAISuggestionRecord,
  EntryAISuggestions,
} from "@/lib/ai/suggestion";
import styles from "./entry-ai-suggestions.module.css";
export function EntryAISuggestionsPanel({
  entryID,
  revision,
  disabled,
  onApply,
}: {
  entryID: string;
  revision: number;
  disabled: boolean;
  onApply: (
    key: keyof EntryAISuggestions,
    value: EntryAISuggestions[keyof EntryAISuggestions],
  ) => void;
}) {
  const [record, setRecord] = useState<EntryAISuggestionRecord | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(true);
  const [unavailable, setUnavailable] = useState(false);
  const [photoCount, setPhotoCount] = useState(0);
  useEffect(() => {
    let active = true;
    fetch("/api/ai/suggestions", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ entryID, revision }),
    })
      .then((r) => r.json())
      .then((data) => {
        if (active) {
          setRecord(data.suggestion ?? null);
          setPhotoCount(data.photoCount ?? 0);
          setUnavailable(data.disabled === true);
          setMessage(data.error ?? null);
        }
      })
      .catch(() => {
        if (active)
          setMessage(
            "Suggestions could not load. Your manual edits still work.",
          );
      })
      .finally(() => {
        if (active) setBusy(false);
      });
    return () => {
      active = false;
    };
  }, [entryID, revision]);
  useEffect(() => {
    if (record?.status !== "generating") return;
    let active = true;
    async function poll() {
      for (let attempt = 0; attempt < 15 && active; attempt++) {
        await new Promise((resolve) => setTimeout(resolve, 2000));
        if (!active) return;
        try {
          const data = await fetch("/api/ai/suggestions", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ entryID, revision }),
          }).then((r) => r.json());
          if (!active) return;
          setRecord(data.suggestion ?? null);
          setPhotoCount(data.photoCount ?? 0);
          setUnavailable(data.disabled === true);
          setMessage(data.error ?? null);
          if (data.suggestion?.status !== "generating") return;
        } catch {
          return;
        }
      }
    }
    void poll();
    return () => {
      active = false;
    };
  }, [entryID, revision, record?.status]);
  async function reload() {
    setBusy(true);
    setMessage(null);
    try {
      const data = await fetch("/api/ai/suggestions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          entryID,
          revision,
          retry: true,
        }),
      }).then((r) => r.json());
      setRecord(data.suggestion ?? null);
      setPhotoCount(data.photoCount ?? 0);
      setUnavailable(data.disabled === true);
      setMessage(data.error ?? null);
    } catch {
      setMessage("Could not reach AI. Try again later.");
    } finally {
      setBusy(false);
    }
  }
  async function dismiss() {
    if (!record) return;
    setBusy(true);
    try {
      const error = await dismissAISuggestion(record.id);
      if (error) setMessage(error);
      else setRecord({ ...record, status: "dismissed" });
    } catch {
      setMessage("Could not dismiss suggestions. Try again.");
    } finally {
      setBusy(false);
    }
  }
  const content = record?.status === "proposed" ? record.suggestions : null;
  return (
    <aside className={styles.panel} aria-label="AI suggestions">
      <div className={styles.heading}>
        <strong>AI suggestions</strong>
        <Link href="/settings/ai">Settings</Link>
      </div>
      <p>
        Optional, based on saved text (up to 16,000 characters). With Photo
        analysis enabled, up to 12 compact photo previews are included, without
        metadata. Choose what to copy, edit freely, then Save.
      </p>
      {photoCount > 0 && (
        <p>Photo previews included: {photoCount}. Originals are not sent.</p>
      )}
      {busy ? (
        <p role="status">Checking suggestions…</p>
      ) : unavailable ? (
        <p>
          AI is off or unavailable on this server. Manual organization stays
          available.
        </p>
      ) : record?.status === "dismissed" ? (
        <p>Suggestions dismissed for this version.</p>
      ) : content ? (
        <>
          <p>{content.rationale}</p>
          <div className={styles.choices}>
            {content.title && (
              <Button
                variant="secondary"
                type="button"
                disabled={disabled}
                onClick={() => onApply("title", content.title)}
              >
                Use title: {content.title}
              </Button>
            )}
            {content.collections.map((name) => (
              <Button
                variant="secondary"
                type="button"
                disabled={disabled}
                key={`c:${name}`}
                onClick={() => onApply("collections", [name])}
              >
                Add Collection: {name}
              </Button>
            ))}
            {content.tags.map((name) => (
              <Button
                variant="secondary"
                type="button"
                disabled={disabled}
                key={`t:${name}`}
                onClick={() => onApply("tags", [name])}
              >
                Add tag: {name}
              </Button>
            ))}
          </div>
          {content.dateText && (
            <p>
              <strong>Date idea:</strong> {content.dateText}
              <br />
              <Button
                variant="secondary"
                type="button"
                disabled={disabled || busy}
                onClick={() => onApply("dateText", content.dateText)}
              >
                Use as approximate date
              </Button>{" "}
              Copies the description only. Review the precision and calendar
              fields below before saving.
            </p>
          )}
          <Button
            variant="secondary"
            type="button"
            disabled={disabled || busy}
            onClick={dismiss}
          >
            Dismiss suggestions
          </Button>
        </>
      ) : (
        <>
          <p>
            {record?.status === "generating"
              ? "Suggestions are being prepared. Check again shortly."
              : "No suggestions are ready yet."}
          </p>
          <Button
            variant="secondary"
            type="button"
            disabled={disabled || busy}
            onClick={reload}
          >
            {record?.status === "failed"
              ? "Retry suggestions"
              : "Check suggestions"}
          </Button>
        </>
      )}
      {message && <p role="status">{message}</p>}
    </aside>
  );
}
