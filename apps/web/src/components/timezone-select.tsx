"use client";

import { useSyncExternalStore, type ChangeEventHandler } from "react";
import {
  commonTimezones,
  supportedTimezones,
  timezoneLabel,
  timezoneOptionLabel,
} from "@/lib/data/timezones";

function subscribeToHydration() {
  return () => {};
}

/**
 * A required native select of IANA time zones, with offsets from the reference date. The caller
 * labels and styles it. Specified in packages/design-system/components/time-zone-field.yaml.
 */
export function TimezoneSelect({
  ariaLabel,
  className,
  disabled = false,
  id,
  onChange,
  referenceDate,
  value,
}: {
  ariaLabel: string;
  className?: string;
  disabled?: boolean;
  /** Lets a visible label point at the select. */
  id?: string;
  onChange: ChangeEventHandler<HTMLSelectElement>;
  referenceDate?: string;
  value: string;
}) {
  const allTimezones = supportedTimezones();
  const commonTimezoneSet = new Set<string>(commonTimezones);
  const currentTimezoneIsListed = allTimezones.includes(value);
  const hydrated = useSyncExternalStore(
    subscribeToHydration,
    () => true,
    () => false,
  );
  const optionLabel = (timezone: string) =>
    hydrated
      ? timezoneOptionLabel(timezone, referenceDate)
      : timezoneLabel(timezone);

  return (
    <select
      aria-label={ariaLabel}
      className={className}
      data-ui-time-zone-field
      disabled={disabled}
      id={id}
      onChange={onChange}
      required
      value={value}
    >
      {!currentTimezoneIsListed ? (
        <optgroup label="Current time zone">
          <option value={value}>{optionLabel(value)}</option>
        </optgroup>
      ) : null}
      <optgroup label="Common time zones">
        {commonTimezones.map((timezone) => (
          <option key={timezone} value={timezone}>
            {optionLabel(timezone)}
          </option>
        ))}
      </optgroup>
      <optgroup label="All time zones">
        {allTimezones
          .filter((timezone) => !commonTimezoneSet.has(timezone))
          .map((timezone) => (
            <option key={timezone} value={timezone}>
              {optionLabel(timezone)}
            </option>
          ))}
      </optgroup>
    </select>
  );
}
