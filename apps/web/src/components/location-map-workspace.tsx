"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import type * as Leaflet from "leaflet";
import { PageFrame } from "@/components/page-frame";
import { PageHeader } from "@/components/page-header";
import { SeparatedList } from "@/components/separated-list";
import { Icon } from "@/components/icon";
import { useEffectiveTheme } from "@/components/use-effective-theme";
import type { LocationMapItem } from "@/lib/data/location-map";
import styles from "./location-map-workspace.module.css";

type MapKind = "all" | LocationMapItem["kind"];
type MapArea = {
  key: string;
  label: string;
  items: LocationMapItem[];
  entryCount: number;
};
const kinds: { label: string; value: MapKind }[] = [
  { label: "All records", value: "all" },
  { label: "Entries", value: "entry" },
  { label: "Entities", value: "entity" },
  { label: "Want to Do", value: "goal" },
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
  const theme = useEffectiveTheme();

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
  const areas = useMemo(() => {
    const grouped = new Map<string, MapArea>();
    for (const item of filtered) {
      const city = item.city?.trim();
      if (!city) continue;
      const region = item.region?.trim();
      const country = item.country?.trim();
      const key = [city, region, country]
        .map((part) => part?.toLocaleLowerCase() ?? "")
        .join("\u0000");
      const area = grouped.get(key) ?? {
        key,
        label: [city, region || country].filter(Boolean).join(", "),
        items: [],
        entryCount: 0,
      };
      area.items.push(item);
      grouped.set(key, area);
    }
    return [...grouped.values()]
      .map((area) => ({
        ...area,
        entryCount: new Set(area.items.map((item) => item.id)).size,
      }))
      .sort(
        (a, b) => b.entryCount - a.entryCount || a.label.localeCompare(b.label),
      )
      .slice(0, 4);
  }, [filtered]);

  function zoomToItems(areaItems: LocationMapItem[]) {
    const map = mapRef.current;
    const L = leafletRef.current;
    if (!map || !L || !areaItems.length) return;
    setSelectedIds(null);
    if (
      areaItems.every(
        (item) =>
          item.latitude === areaItems[0].latitude &&
          item.longitude === areaItems[0].longitude,
      )
    ) {
      map.setView([areaItems[0].latitude, areaItems[0].longitude], 11, {
        animate: false,
      });
      return;
    }
    map.fitBounds(
      L.latLngBounds(areaItems.map((item) => [item.latitude, item.longitude])),
      { padding: [48, 48], maxZoom: 11, animate: false },
    );
  }

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
        zoomAnimation: false,
      });
      mapRef.current = map;
      setReady(true);
    }
    void initialize();
    return () => {
      disposed = true;
      map?.remove();
      mapRef.current = null;
    };
  }, []);

  useEffect(() => {
    const map = mapRef.current;
    const L = leafletRef.current;
    if (!ready || !mapConfigured || !theme || !map || !L) return;

    setTileError(false);
    const onTileError = () => setTileError(true);
    const tiles = L.tileLayer(
      `/api/locations/tiles/{z}/{x}/{y}?theme=${theme}`,
      { maxZoom: 19, minZoom: 2, tileSize: 256 },
    )
      .on("tileerror", onTileError)
      .addTo(map);
    return () => {
      tiles.off("tileerror", onTileError);
      tiles.remove();
    };
  }, [mapConfigured, ready, theme]);

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
          animate: false,
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

      {areas.length > 1 ? (
        <section aria-labelledby="map-areas-heading" className={styles.areas}>
          <div className={styles.areasHead}>
            <h2 id="map-areas-heading">Your areas</h2>
            <button
              className={styles.allAreasButton}
              onClick={() => zoomToItems(filtered)}
              type="button"
            >
              View all
            </button>
          </div>
          <div className={styles.areaActions}>
            {areas.map((area) => (
              <button
                aria-label={`Zoom to ${area.label}, ${area.entryCount} ${area.entryCount === 1 ? "Entry" : "Entries"}`}
                className={styles.areaButton}
                key={area.key}
                onClick={() => zoomToItems(area.items)}
                type="button"
              >
                <span>{area.label}</span>
                <small>{area.entryCount}</small>
              </button>
            ))}
          </div>
        </section>
      ) : null}

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
            data-map-theme={theme ?? undefined}
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
            <SeparatedList className={styles.attributionLinks}>
              <span>
                Map data{" "}
                <a
                  href="https://www.openstreetmap.org/copyright"
                  rel="noreferrer"
                  target="_blank"
                >
                  © OpenStreetMap contributors
                </a>
              </span>
              <a
                href="https://openmaptiles.org/"
                rel="noreferrer"
                target="_blank"
              >
                © OpenMapTiles
              </a>
              <a
                href="https://www.geoapify.com/"
                rel="noreferrer"
                target="_blank"
              >
                Geoapify
              </a>
            </SeparatedList>
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
                      <SeparatedList spacing="word">
                        <span>{item.kind}</span>
                        <span>{item.address}</span>
                        {item.occurredAt ? (
                          <span>{item.occurredAt.slice(0, 10)}</span>
                        ) : null}
                      </SeparatedList>
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
