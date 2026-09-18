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
  const [latitude, setLatitude] = useState(value.latitude?.toString() ?? "");
  const [longitude, setLongitude] = useState(value.longitude?.toString() ?? "");
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
      setOptions(data.places);
      setMessage(
        data.hasMore
          ? "First 100 Places shown. Refine your search."
          : data.places.length
            ? null
            : "No matching Places.",
      );
    } catch {
      setMessage("Places could not be loaded. Try again.");
    } finally {
      setBusy(false);
    }
  }
  return (
    <fieldset disabled={disabled || busy}>
      <legend>Place to add when you save</legend>
      <p>
        No Place is created or linked until Save changes or Done. Existing links
        stay unchanged.
      </p>
      {value.kind === "new" ? (
        <>
          <label>
            New Place name
            <input
              maxLength={200}
              value={value.name ?? ""}
              onChange={(e) => onChange({ ...value, name: e.target.value })}
            />
          </label>
          <label>
            Latitude
            <input
              inputMode="decimal"
              value={latitude}
              onChange={(e) => {
                setLatitude(e.target.value);
                onChange({
                  ...value,
                  latitude:
                    e.target.value === "" ? undefined : Number(e.target.value),
                });
              }}
            />
          </label>
          <label>
            Longitude
            <input
              inputMode="decimal"
              value={longitude}
              onChange={(e) => {
                setLongitude(e.target.value);
                onChange({
                  ...value,
                  longitude:
                    e.target.value === "" ? undefined : Number(e.target.value),
                });
              }}
            />
          </label>
          <p>
            Coordinates came from this photo. Review or correct them; no address
            is inferred.
          </p>
        </>
      ) : (
        <p>
          Link existing Place: {value.name}. Its name, coordinates, and other
          facts will not change.
        </p>
      )}
      <label>
        Find an existing Place
        <input
          maxLength={200}
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
      </label>
      <Button variant="secondary" type="button" onClick={() => void search()}>
        Search Places
      </Button>
      {options.length ? (
        <label>
          Existing Place
          <select
            aria-label="Existing Place"
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
            <option value="">Choose a Place</option>
            {options.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
                {p.latitude !== null ? ` (${p.latitude}, ${p.longitude})` : ""}
              </option>
            ))}
          </select>
        </label>
      ) : null}
      {message ? <p role="status">{message}</p> : null}
      <Button variant="secondary" type="button" onClick={() => onChange(null)}>
        Remove Place from draft
      </Button>
    </fieldset>
  );
}
