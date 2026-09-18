"use client";
import { Button } from "@/components/button";
import { useState } from "react";
import type {
  PhotoPlaceDraft,
  PhotoPlaceOption,
} from "@/lib/media/photo-place";
export function PhotoPlaceEditor({
  value,
  onChange,
  disabled,
}: {
  value: PhotoPlaceDraft;
  onChange: (value: PhotoPlaceDraft | null) => void;
  disabled: boolean;
}) {
  const [query, setQuery] = useState("");
  const [options, setOptions] = useState<PhotoPlaceOption[]>([]);
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  async function search() {
    setBusy(true);
    setMessage(null);
    try {
      const response = await fetch(
        `/api/media/place-options?query=${encodeURIComponent(query)}`,
        { method: "POST" },
      );
      if (!response.ok) throw Error();
      const data = await response.json();
      setOptions(data.locations);
      setMessage(
        data.hasMore
          ? "First 100 Locations shown. Refine your search."
          : data.locations.length
            ? null
            : "No matching Locations.",
      );
    } catch {
      setMessage("Locations could not be loaded. Try again.");
    } finally {
      setBusy(false);
    }
  }
  return (
    <fieldset disabled={disabled || busy}>
      <legend>Location to add when you save</legend>
      <p>
        No Location is created or linked until Save changes or Done. Existing
        links stay unchanged.
      </p>
      {value.kind === "new" ? (
        <>
          <label>
            New Location name
            <input
              maxLength={200}
              value={value.name ?? ""}
              onChange={(e) => onChange({ ...value, name: e.target.value })}
            />
          </label>
          <p>
            Geographic coordinates came from this photo and stay private. No
            address is inferred.
          </p>
        </>
      ) : (
        <p>
          Link existing Location: {value.name}. Its name, coordinates, and other
          facts will not change.
        </p>
      )}
      <label>
        Find an existing Location
        <input
          maxLength={200}
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
      </label>
      <Button variant="secondary" type="button" onClick={() => void search()}>
        Search Locations
      </Button>
      {options.length ? (
        <label>
          Existing Location
          <select
            aria-label="Existing Location"
            value={value.placeId ?? ""}
            onChange={(e) => {
              const p = options.find((p) => p.id === e.target.value);
              if (p)
                onChange({
                  kind: "existing",
                  attachmentId: value.attachmentId,
                  placeId: p.id,
                  revision: p.revision,
                  name: p.name,
                });
            }}
          >
            <option value="">Choose a Location</option>
            {options.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
          </select>
        </label>
      ) : null}
      {message ? <p role="status">{message}</p> : null}
      <Button variant="secondary" type="button" onClick={() => onChange(null)}>
        Remove Location from draft
      </Button>
    </fieldset>
  );
}
