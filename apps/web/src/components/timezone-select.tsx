"use client";

import type { ChangeEventHandler } from "react";
import {
  commonTimezones,
  supportedTimezones,
  timezoneLabel,
} from "@/lib/data/timezones";

export function TimezoneSelect({
  ariaLabel,
  className,
  disabled = false,
  onChange,
  value,
}: {
  ariaLabel: string;
  className?: string;
  disabled?: boolean;
  onChange: ChangeEventHandler<HTMLSelectElement>;
  value: string;
}) {
  const allTimezones = supportedTimezones();
  const commonTimezoneSet = new Set<string>(commonTimezones);
  const currentTimezoneIsListed = allTimezones.includes(value);

  return (
    <select
      aria-label={ariaLabel}
      className={className}
      disabled={disabled}
      onChange={onChange}
      required
      value={value}
    >
      {!currentTimezoneIsListed ? (
        <optgroup label="Current time zone">
          <option value={value}>{timezoneLabel(value)}</option>
        </optgroup>
      ) : null}
      <optgroup label="Common time zones">
        {commonTimezones.map((timezone) => (
          <option key={timezone} value={timezone}>
            {timezoneLabel(timezone)}
          </option>
        ))}
      </optgroup>
      <optgroup label="All time zones">
        {allTimezones
          .filter((timezone) => !commonTimezoneSet.has(timezone))
          .map((timezone) => (
            <option key={timezone} value={timezone}>
              {timezoneLabel(timezone)}
            </option>
          ))}
      </optgroup>
    </select>
  );
}
