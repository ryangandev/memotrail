"use client";

import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import Image from "next/image";
import { Button } from "@/components/button";
import { Icon } from "@/components/icon";
import {
  locationSubtitle,
  type ExistingLocation,
  type LocationSelection,
  type ProviderLocation,
} from "@/lib/locations/location";
import styles from "./location-picker.module.css";

type SearchResponse = {
  configured: boolean;
  provider: ProviderLocation[];
  providerUnavailable: boolean;
  saved: ExistingLocation[];
};

export function LocationPicker({
  allowRemove = true,
  disabled,
  onChange,
  subject = "Entry",
  value,
}: {
  allowRemove?: boolean;
  disabled: boolean;
  onChange: (value: LocationSelection | null) => void;
  subject?: "Entry" | "Home";
  value: LocationSelection | null;
}) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchResponse | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const searchRequest = useRef(0);
  const searchTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(
    () => () => {
      if (searchTimer.current) clearTimeout(searchTimer.current);
      searchRequest.current += 1;
    },
    [],
  );

  async function search(searchQuery = query) {
    const normalized = searchQuery.trim();
    if (normalized.length < 2) {
      setMessage("Type at least 2 characters to search.");
      return;
    }
    const request = ++searchRequest.current;
    setBusy(true);
    setMessage(null);
    try {
      const language = navigator.language.split("-", 1)[0] ?? "en";
      const response = await fetch(
        `/api/locations/search?query=${encodeURIComponent(normalized)}&lang=${encodeURIComponent(language)}`,
        { method: "POST" },
      );
      if (!response.ok) throw new Error("location_search_failed");
      const data = (await response.json()) as SearchResponse;
      if (request !== searchRequest.current) return;
      setResults(data);
      if (!data.saved.length && !data.provider.length) {
        setMessage(
          data.configured
            ? "No matching Locations or addresses."
            : "No saved Locations matched. Address search will be available after Geoapify is configured.",
        );
      } else if (data.providerUnavailable) {
        setMessage(
          "Saved Locations are shown, but address search is temporarily unavailable.",
        );
      }
    } catch {
      if (request === searchRequest.current) {
        setMessage("Locations could not be searched. Try again.");
      }
    } finally {
      if (request === searchRequest.current) setBusy(false);
    }
  }

  function changeQuery(nextQuery: string) {
    if (searchTimer.current) clearTimeout(searchTimer.current);
    searchRequest.current += 1;
    setQuery(nextQuery);
    setResults(null);
    setMessage(null);
    setBusy(false);
    if (nextQuery.trim().length >= 2) {
      searchTimer.current = setTimeout(() => void search(nextQuery), 350);
    }
  }

  function searchNow() {
    if (searchTimer.current) clearTimeout(searchTimer.current);
    void search();
  }

  function selectLocation(location: LocationSelection) {
    if (searchTimer.current) clearTimeout(searchTimer.current);
    searchRequest.current += 1;
    setBusy(false);
    setQuery("");
    setResults(null);
    setMessage(null);
    onChange(location);
  }

  function handleKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key !== "Enter") return;
    event.preventDefault();
    searchNow();
  }

  return (
    <section
      aria-labelledby="location-picker-heading"
      className={styles.picker}
    >
      <div className={styles.heading}>
        <div className={styles.headingIcon}>
          <Icon name="map" size={18} />
        </div>
        <div>
          <strong id="location-picker-heading">Location</strong>
          <p>
            Reuse a saved Location or find an address. Choosing a different
            Location changes only this {subject}.
          </p>
        </div>
      </div>

      {value ? (
        <SelectedLocation
          disabled={disabled}
          location={value}
          onRemove={allowRemove ? () => onChange(null) : null}
        />
      ) : null}

      <div className={styles.searchRow}>
        <label>
          <span>{value ? "Change Location" : "Find a Location"}</span>
          <div className={styles.searchInput}>
            <Icon name="search" size={17} />
            <input
              autoComplete="off"
              disabled={disabled}
              maxLength={200}
              onChange={(event) => changeQuery(event.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="Search a saved Location or address"
              value={query}
            />
          </div>
        </label>
        <Button
          disabled={disabled || busy}
          onClick={searchNow}
          type="button"
          variant="secondary"
        >
          {busy ? "Searching..." : "Search"}
        </Button>
      </div>

      {results?.saved.length ? (
        <ResultGroup
          label="Saved Locations"
          locations={results.saved}
          onSelect={selectLocation}
        />
      ) : null}
      {results?.provider.length ? (
        <ResultGroup
          label="Address results"
          locations={results.provider}
          onSelect={selectLocation}
        />
      ) : null}
      {results && !results.configured ? (
        <p className={styles.configurationNote}>
          Geoapify is not configured yet. Saved Location search works now;
          address search and the full map will turn on when the server key is
          added.
        </p>
      ) : null}
      {results?.provider.length ? (
        <p className={styles.attribution}>
          Powered by{" "}
          <a href="https://www.geoapify.com/" rel="noreferrer" target="_blank">
            Geoapify
          </a>{" "}
          ·{" "}
          <a
            href="https://www.openstreetmap.org/copyright"
            rel="noreferrer"
            target="_blank"
          >
            © OpenStreetMap contributors
          </a>
        </p>
      ) : null}
      {message ? (
        <p className={styles.message} role="status">
          {message}
        </p>
      ) : null}
    </section>
  );
}

function SelectedLocation({
  disabled,
  location,
  onRemove,
}: {
  disabled: boolean;
  location: LocationSelection;
  onRemove: (() => void) | null;
}) {
  const subtitle = locationSubtitle(location);
  const latitude = location.latitude;
  const longitude = location.longitude;
  const hasCoordinates = latitude !== null && longitude !== null;
  return (
    <div className={styles.selected}>
      {hasCoordinates ? (
        <Image
          alt={`Map showing ${location.name}`}
          className={styles.map}
          height={280}
          loading="lazy"
          src={`/api/locations/map?lat=${latitude}&lon=${longitude}`}
          width={720}
          unoptimized
        />
      ) : (
        <div className={styles.mapUnavailable}>
          <Icon name="map" size={24} />
          <span>This saved Location does not have coordinates yet.</span>
        </div>
      )}
      <div className={styles.selectedSummary}>
        <div>
          <strong>{location.name}</strong>
          {subtitle ? <span>{subtitle}</span> : null}
        </div>
        {onRemove ? (
          <Button
            disabled={disabled}
            onClick={onRemove}
            size="small"
            type="button"
            variant="secondary"
          >
            Remove
          </Button>
        ) : null}
      </div>
      {hasCoordinates ? (
        <div className={styles.coordinates}>
          <span>
            {latitude.toFixed(5)}, {longitude.toFixed(5)}
          </span>
          <a
            href={`https://www.openstreetmap.org/?mlat=${latitude}&mlon=${longitude}#map=16/${latitude}/${longitude}`}
            rel="noreferrer"
            target="_blank"
          >
            Open map
          </a>
        </div>
      ) : null}
    </div>
  );
}

function ResultGroup({
  label,
  locations,
  onSelect,
}: {
  label: string;
  locations: LocationSelection[];
  onSelect: (location: LocationSelection) => void;
}) {
  return (
    <div className={styles.results}>
      <strong>{label}</strong>
      <div>
        {locations.map((location) => (
          <button
            key={
              location.kind === "existing"
                ? location.id
                : `${location.provider}:${location.providerLocationId}`
            }
            onClick={() => onSelect(location)}
            type="button"
          >
            <span className={styles.resultIcon}>
              <Icon name="map" size={16} />
            </span>
            <span>
              <strong>{location.name}</strong>
              <small>{locationSubtitle(location)}</small>
            </span>
            <Icon name="chevron" size={15} />
          </button>
        ))}
      </div>
    </div>
  );
}
