"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import type * as Leaflet from "leaflet";
import { PageFrame } from "@/components/page-frame";
import { PageHeader } from "@/components/page-header";
import { Icon } from "@/components/icon";
import type { LocationMapItem } from "@/lib/data/location-map";
import styles from "./location-map-workspace.module.css";

type MapKind = "all" | LocationMapItem["kind"];
const kinds: { label: string; value: MapKind }[] = [
  { label: "All records", value: "all" },
  { label: "Entries", value: "entry" },
  { label: "Entities", value: "entity" },
  { label: "Goals", value: "goal" },
];

export function LocationMapWorkspace({
  items,
  loadError,
  mapConfigured,
  truncated,
}: {
  items: LocationMapItem[];
  loadError: string | null;
  mapConfigured: boolean;
  truncated: boolean;
}) {
  const elementRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<Leaflet.Map | null>(null);
  const leafletRef = useRef<typeof Leaflet | null>(null);
  const [ready, setReady] = useState(false);
  const [kind, setKind] = useState<MapKind>("all");
  const [fromYear, setFromYear] = useState("");
  const [toYear, setToYear] = useState("");
  const [selectedIds, setSelectedIds] = useState<string[] | null>(null);
  const [tileError, setTileError] = useState(false);

  const filtered = useMemo(
    () =>
      items.filter((item) => {
        if (kind !== "all" && item.kind !== kind) return false;
        const year = item.occurredAt
          ? new Date(item.occurredAt).getUTCFullYear()
          : null;
        if (fromYear && (year === null || year < Number(fromYear)))
          return false;
        if (toYear && (year === null || year > Number(toYear))) return false;
        return true;
      }),
    [items, kind, fromYear, toYear],
  );

  useEffect(() => {
    let disposed = false;
    let map: Leaflet.Map | null = null;
    async function initialize() {
      const L = await import("leaflet");
      if (disposed || !elementRef.current) return;
      leafletRef.current = L;
      map = L.map(elementRef.current, {
        center: [20, 0],
        zoom: 2,
        minZoom: 2,
        maxZoom: 19,
        worldCopyJump: true,
        attributionControl: false,
      });
      mapRef.current = map;
      if (mapConfigured) {
        L.tileLayer("/api/locations/tiles/{z}/{x}/{y}", {
          maxZoom: 19,
          minZoom: 2,
          tileSize: 256,
        })
          .on("tileerror", () => setTileError(true))
          .addTo(map);
      }
      setReady(true);
    }
    void initialize();
    return () => {
      disposed = true;
      map?.remove();
      mapRef.current = null;
    };
  }, [mapConfigured]);

  useEffect(() => {
    const map = mapRef.current;
    const L = leafletRef.current;
    if (!ready || !map || !L) return;
    const layer = L.layerGroup().addTo(map);
    function draw() {
      layer.clearLayers();
      const groups = new Map<string, LocationMapItem[]>();
      const bounds = map!.getBounds().pad(0.2);
      for (const item of filtered) {
        if (!bounds.contains([item.latitude, item.longitude])) continue;
        const point = map!.latLngToContainerPoint([
          item.latitude,
          item.longitude,
        ]);
        const cell = `${Math.floor(point.x / 64)}:${Math.floor(point.y / 64)}`;
        const group = groups.get(cell) ?? [];
        group.push(item);
        groups.set(cell, group);
      }
      for (const group of groups.values()) {
        const latitude =
          group.reduce((sum, item) => sum + item.latitude, 0) / group.length;
        const longitude =
          group.reduce((sum, item) => sum + item.longitude, 0) / group.length;
        const count = group.length;
        const marker = L!.marker([latitude, longitude], {
          icon: L!.divIcon({
            className: count > 1 ? styles.cluster : styles.pin,
            html: `<span>${count > 1 ? count : ""}</span>`,
            iconSize: count > 1 ? [42, 42] : [24, 24],
          }),
          title:
            count > 1
              ? `${count} Entry locations in this area`
              : group[0].title,
          keyboard: true,
        });
        marker.on("click", () => {
          setSelectedIds(group.map((item) => `${item.id}:${item.locationId}`));
          if (group.length > 1 && map!.getZoom() < 16) {
            map!.setView(
              [latitude, longitude],
              Math.min(map!.getZoom() + 2, 16),
            );
          }
        });
        marker.addTo(layer);
      }
    }
    map.on("moveend zoomend", draw);
    if (filtered.length) {
      map.fitBounds(
        L.latLngBounds(filtered.map((item) => [item.latitude, item.longitude])),
        {
          padding: [48, 48],
          maxZoom: 13,
        },
      );
    } else {
      map.setView([20, 0], 2);
    }
    draw();
    return () => {
      map.off("moveend zoomend", draw);
      layer.remove();
    };
  }, [filtered, ready]);

  const selected = selectedIds
    ? filtered.filter((item) =>
        selectedIds.includes(`${item.id}:${item.locationId}`),
      )
    : [];
  const sorted = [
    ...new Map(
      [...selected]
        .sort((a, b) => (b.occurredAt ?? "").localeCompare(a.occurredAt ?? ""))
        .map((item) => [item.id, item]),
    ).values(),
  ];

  return (
    <PageFrame variant="standard">
      <PageHeader
        eyebrow={<>Your life in places</>}
        title={<>Map</>}
        description={
          <>
            Explore the current coordinates attached to your memories, events,
            and other Wiki Items.
          </>
        }
      />
      <div className={styles.filters} aria-label="Map filters">
        <label>
          <span>Category</span>
          <select
            value={kind}
            onChange={(event) => {
              setKind(event.target.value as MapKind);
              setSelectedIds(null);
            }}
          >
            {kinds.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </label>
        <label>
          <span>From year</span>
          <input
            inputMode="numeric"
            max="9999"
            min="1"
            onChange={(event) => {
              setFromYear(event.target.value);
              setSelectedIds(null);
            }}
            placeholder="Any"
            type="number"
            value={fromYear}
          />
        </label>
        <label>
          <span>To year</span>
          <input
            inputMode="numeric"
            max="9999"
            min="1"
            onChange={(event) => {
              setToYear(event.target.value);
              setSelectedIds(null);
            }}
            placeholder="Any"
            type="number"
            value={toYear}
          />
        </label>
        <p role="status">
          {filtered.length} Entry{" "}
          {filtered.length === 1 ? "Location" : "Locations"}
        </p>
      </div>

      {loadError ? (
        <p className={styles.notice} role="alert">
          {loadError}
        </p>
      ) : null}
      {truncated ? (
        <p className={styles.notice}>
          Showing the 5,000 most recently linked Locations. Filters apply only
          to these results.
        </p>
      ) : null}
      <div className={styles.layout}>
        <div className={styles.mapWrap}>
          <div
            aria-label="Interactive map of your Entry Locations"
            className={styles.map}
            ref={elementRef}
            role="region"
          />
          {!mapConfigured ? (
            <p className={styles.mapNotice}>
              Map tiles need the server Geoapify key. Your coordinate pins
              remain available.
            </p>
          ) : null}
          {tileError ? (
            <p className={styles.mapNotice}>
              Some map tiles are unavailable right now. Your Entries are still
              shown.
            </p>
          ) : null}
          <p className={styles.attribution}>
            Map data{" "}
            <a
              href="https://www.openstreetmap.org/copyright"
              rel="noreferrer"
              target="_blank"
            >
              © OpenStreetMap contributors
            </a>
            {" · "}
            <a
              href="https://www.geoapify.com/"
              rel="noreferrer"
              target="_blank"
            >
              Geoapify
            </a>
          </p>
        </div>
        <aside
          aria-label="Entries at selected Location"
          className={styles.detail}
        >
          <div className={styles.detailHead}>
            <Icon name="map" size={18} />
            <h2>
              {sorted.length
                ? `${sorted.length} ${sorted.length === 1 ? "Entry" : "Entries"} here`
                : "Choose a map point"}
            </h2>
          </div>
          {sorted.length ? (
            <ul>
              {sorted.map((item) => (
                <li key={`${item.id}:${item.locationId}`}>
                  <Link href={item.href}>
                    <span>{item.title}</span>
                    <small>
                      {item.kind} · {item.address}
                      {item.occurredAt
                        ? ` · ${item.occurredAt.slice(0, 10)}`
                        : ""}
                    </small>
                  </Link>
                </li>
              ))}
            </ul>
          ) : (
            <p>
              {filtered.length
                ? "Pan, zoom, or select a pin to see what happened there."
                : "No current Entries match these filters. Add a Location in an Entry to place it on this map."}
            </p>
          )}
        </aside>
      </div>
    </PageFrame>
  );
}
