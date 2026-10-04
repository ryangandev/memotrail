"use client";

import { useEffect, useId, useRef, useState, type KeyboardEvent } from "react";
import { Button } from "@/components/button";
import { Icon } from "@/components/icon";
import { SearchField } from "@/components/search-field";
import { SeparatedList } from "@/components/separated-list";
import {
  locationDisplayLabel,
  type ProviderLocation,
} from "@/lib/locations/location";
import styles from "./location-picker.module.css";

type SearchResponse = {
  configured: boolean;
  provider: ProviderLocation[];
  providerUnavailable: boolean;
};

export function AddressSearch({
  disabled,
  label,
  onSelect,
}: {
  disabled: boolean;
  label: string;
  onSelect: (location: ProviderLocation) => void;
}) {
  const resultId = useId();
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchResponse | null>(null);
  const [activeIndex, setActiveIndex] = useState(-1);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const requestId = useRef(0);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(
    () => () => {
      if (timer.current) clearTimeout(timer.current);
      requestId.current += 1;
    },
    [],
  );

  async function search(value = query) {
    const normalized = value.trim();
    if (normalized.length < 2) {
      setMessage("Type at least 2 characters to search.");
      return;
    }
    const request = ++requestId.current;
    setBusy(true);
    setMessage(null);
    try {
      const language = navigator.language.split("-", 1)[0] ?? "en";
      const response = await fetch(
        `/api/locations/search?query=${encodeURIComponent(normalized)}&lang=${encodeURIComponent(language)}`,
        { method: "POST" },
      );
      if (response.status === 429) throw new Error("location_rate_limit");
      if (!response.ok) throw new Error("location_search_failed");
      const data = (await response.json()) as SearchResponse;
      if (request !== requestId.current) return;
      setResults(data);
      setActiveIndex(-1);
      if (!data.provider.length) {
        setMessage(
          data.configured
            ? "No matching addresses."
            : "Address search will be available after Geoapify is configured.",
        );
      }
      if (data.providerUnavailable)
        setMessage("Address search is temporarily unavailable.");
    } catch (error) {
      if (request === requestId.current) {
        setResults(null);
        setMessage(
          error instanceof Error && error.message === "location_rate_limit"
            ? "Address search is paused for this hour. Try again later."
            : "Addresses could not be searched. Try again.",
        );
      }
    } finally {
      if (request === requestId.current) setBusy(false);
    }
  }

  function changeQuery(nextQuery: string) {
    if (timer.current) clearTimeout(timer.current);
    requestId.current += 1;
    setQuery(nextQuery);
    setResults(null);
    setActiveIndex(-1);
    setMessage(null);
    setBusy(false);
    if (nextQuery.trim().length >= 2) {
      timer.current = setTimeout(() => void search(nextQuery), 350);
    }
  }

  function select(location: ProviderLocation) {
    if (timer.current) clearTimeout(timer.current);
    requestId.current += 1;
    setBusy(false);
    setQuery("");
    setResults(null);
    setActiveIndex(-1);
    setMessage(null);
    onSelect(location);
  }

  function handleKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    const locations = results?.provider ?? [];
    if (event.key === "ArrowDown" && locations.length) {
      event.preventDefault();
      setActiveIndex((current) => (current + 1) % locations.length);
    } else if (event.key === "ArrowUp" && locations.length) {
      event.preventDefault();
      setActiveIndex((current) =>
        current <= 0 ? locations.length - 1 : current - 1,
      );
    } else if (event.key === "Escape") {
      if (timer.current) clearTimeout(timer.current);
      requestId.current += 1;
      setBusy(false);
      setResults(null);
      setActiveIndex(-1);
    } else if (event.key === "Enter") {
      event.preventDefault();
      if (activeIndex >= 0 && locations[activeIndex])
        select(locations[activeIndex]);
      else {
        if (timer.current) clearTimeout(timer.current);
        void search();
      }
    }
  }

  const locations = results?.provider ?? [];
  return (
    <div>
      <div className={styles.searchRow}>
        <SearchField
          aria-activedescendant={
            activeIndex >= 0 ? `${resultId}-${activeIndex}` : undefined
          }
          aria-autocomplete="list"
          aria-controls={locations.length ? resultId : undefined}
          aria-expanded={locations.length > 0}
          disabled={disabled}
          label={label}
          maxLength={200}
          onChange={(event) => changeQuery(event.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="Search for an address"
          role="combobox"
          value={query}
        />
        <Button
          disabled={disabled || busy}
          onClick={() => {
            if (timer.current) clearTimeout(timer.current);
            void search();
          }}
          type="button"
          variant="secondary"
        >
          {busy ? "Searching..." : "Search"}
        </Button>
      </div>

      {locations.length ? (
        <div className={styles.results}>
          <strong>Address results</strong>
          <div id={resultId} role="listbox" aria-label="Address results">
            {locations.map((location, index) => (
              <button
                aria-selected={activeIndex === index}
                id={`${resultId}-${index}`}
                key={`${location.provider}:${location.providerLocationId}`}
                onClick={() => select(location)}
                onMouseEnter={() => setActiveIndex(index)}
                role="option"
                type="button"
              >
                <span className={styles.resultIcon}>
                  <Icon name="map" size={16} />
                </span>
                <span>
                  <strong>{locationDisplayLabel(location)}</strong>
                  <small>
                    {[location.city, location.region, location.country]
                      .filter(Boolean)
                      .join(", ")}
                  </small>
                </span>
                <Icon name="chevron" size={15} />
              </button>
            ))}
          </div>
        </div>
      ) : null}
      {results && !results.configured ? (
        <p className={styles.configurationNote}>
          Geoapify is not configured yet. Address search and map previews need
          the server key.
        </p>
      ) : null}
      {locations.length ? (
        <p className={styles.attribution}>
          <SeparatedList align="end" className={styles.attributionLinks}>
            <span>
              Powered by{" "}
              <a
                href="https://www.geoapify.com/"
                rel="noreferrer"
                target="_blank"
              >
                Geoapify
              </a>
            </span>
            <a
              href="https://www.openstreetmap.org/copyright"
              rel="noreferrer"
              target="_blank"
            >
              © OpenStreetMap contributors
            </a>
          </SeparatedList>
        </p>
      ) : null}
      {message ? (
        <p className={styles.message} role="status">
          {message}
        </p>
      ) : null}
    </div>
  );
}
