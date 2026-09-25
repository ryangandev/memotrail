"use client";

import Image from "next/image";
import { AddressSearch } from "@/components/address-search";
import { Button } from "@/components/button";
import { Icon } from "@/components/icon";
import { useEffectiveTheme } from "@/components/use-effective-theme";
import {
  locationDisplayLabel,
  type LocationSelection,
} from "@/lib/locations/location";
import styles from "./location-picker.module.css";

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
  return (
    <section aria-label="Location" className={styles.picker}>
      <div className={styles.heading}>
        <div className={styles.headingIcon}>
          <Icon name="map" size={18} />
        </div>
        <div>
          <strong>Location</strong>
          <p>
            Search for an address and preview its position. This {subject} keeps
            its own Location.
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
      <AddressSearch
        disabled={disabled}
        label={value ? "Change Location" : "Find a Location"}
        onSelect={onChange}
      />
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
  const label = locationDisplayLabel(location);
  const latitude = location.latitude;
  const longitude = location.longitude;
  const hasCoordinates = latitude !== null && longitude !== null;
  const theme = useEffectiveTheme();
  return (
    <div className={styles.selected}>
      {hasCoordinates && theme ? (
        <Image
          alt={`Map showing ${label}`}
          className={styles.map}
          height={280}
          loading="lazy"
          src={`/api/locations/map?lat=${latitude}&lon=${longitude}&theme=${theme}`}
          width={720}
          unoptimized
        />
      ) : hasCoordinates ? (
        <div aria-hidden="true" className={styles.mapUnavailable} />
      ) : (
        <div className={styles.mapUnavailable}>
          <Icon name="map" size={24} />
          <span>This Location does not have coordinates yet.</span>
        </div>
      )}
      <div className={styles.selectedSummary}>
        <div>
          <strong>{label}</strong>
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
