"use client";
import { Button } from "@/components/button";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { saveTrack } from "@/app/timeline/tracks/actions";
import {
  validTrackInput,
  type TrackSetting,
  type TrackInput,
} from "@/lib/data/tracks";
import styles from "@/components/track-settings.module.css";
export function TrackSettings({ tracks }: { tracks: TrackSetting[] }) {
  const [adding, setAdding] = useState(false);
  const [generation, setGeneration] = useState(0);
  const router = useRouter();
  return (
    <>
      <div className={styles.actions}>
        <Button
          variant="secondary"
          type="button"
          onClick={() => setAdding(!adding)}
        >
          {adding ? "Cancel new track" : "Add track"}
        </Button>
        <Button
          variant="secondary"
          type="button"
          onClick={() => {
            setGeneration((value) => value + 1);
            router.refresh();
          }}
        >
          Reload tracks
        </Button>
      </div>
      <p className={styles.hint}>
        Lower order numbers appear first. Equal numbers sort by name. Reloading
        discards unsaved track edits.
      </p>
      {adding && (
        <TrackForm
          key={`new:${generation}`}
          onSaved={() => {
            setAdding(false);
            router.refresh();
          }}
        />
      )}
      <div className={styles.list}>
        {tracks.map((track) => (
          <TrackForm
            key={`${track.id}:${track.revision}:${generation}`}
            onSaved={() => router.refresh()}
            track={track}
          />
        ))}
        {tracks.length === 0 && (
          <p>
            No tracks on this page. Add a track or return to an earlier page.
          </p>
        )}
      </div>
    </>
  );
}
function TrackForm({
  track,
  onSaved,
}: {
  track?: TrackSetting;
  onSaved?: () => void;
}) {
  const [name, setName] = useState(track?.name ?? "");
  const [order, setOrder] = useState(String(track?.sort_order ?? 0));
  const [hidden, setHidden] = useState(track?.is_hidden ?? false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const input: TrackInput = {
    id: track?.id ?? null,
    revision: track?.revision ?? null,
    name,
    order: order.trim() ? Number(order) : NaN,
    hidden,
  };
  return (
    <form
      className={styles.card}
      aria-label={track ? `Edit ${track.name}` : "New track"}
      onSubmit={async (event) => {
        event.preventDefault();
        if (busy || !validTrackInput(input)) return;
        setBusy(true);
        setMessage(null);
        try {
          const error = await saveTrack(input);
          setMessage(error ?? "Track saved.");
          if (!error) onSaved?.();
        } catch {
          setMessage("Could not connect. Your edits are still here to retry.");
        } finally {
          setBusy(false);
        }
      }}
    >
      <div className={styles.cardHeading}>
        <h2>{track?.name ?? "New track"}</h2>
        <span>
          {track
            ? `${track.system_key ? "Default" : "Custom"} · ${track.entry_count} ${track.entry_count === 1 ? "moment" : "moments"}${track.is_hidden ? " · Hidden" : ""}`
            : "A new dimension of your story"}
        </span>
      </div>
      <fieldset disabled={busy}>
        <div className={styles.fields}>
          <label>
            Name
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              required
              maxLength={100}
              autoComplete="off"
            />
          </label>
          <label>
            Order
            <input
              type="number"
              value={order}
              onChange={(e) => setOrder(e.target.value)}
              required
              min={-1000000}
              max={1000000}
              step={1}
            />
          </label>
        </div>
        <label className={styles.toggle}>
          <input
            type="checkbox"
            checked={hidden}
            onChange={(e) => setHidden(e.target.checked)}
          />
          Hide from Timeline
        </label>
        <Button
          variant="primary"
          type="submit"
          disabled={!validTrackInput(input)}
        >
          {busy ? "Saving…" : track ? "Save track" : "Create track"}
        </Button>
      </fieldset>
      {message && <p role="status">{message}</p>}
    </form>
  );
}
