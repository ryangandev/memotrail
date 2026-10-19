"use client";

import { useState } from "react";
import { Button } from "@/components/button";
import { Checkbox } from "@/components/checkbox";
import { DatePickerField } from "@/components/date-picker-field";
import { SearchField } from "@/components/search-field";
import { SegmentedControl } from "@/components/segmented-control";
import { SelectField } from "@/components/select-field";
import { TextField } from "@/components/text-field";
import { TimezoneSelect } from "@/components/timezone-select";
import styles from "./page.module.css";
import controls from "./controls-gallery.module.css";
import { Specimen, SpecimenCase } from "./specimen";

/**
 * The form controls from packages/design-system/components: TextField, SearchField, SelectField,
 * Checkbox, SegmentedControl, DateField, and TimeZoneField, each with its spec's specimens. The iOS gallery draws the
 * same specimens with the same content in GalleryForms.swift.
 */
export function FormControlSpecimens() {
  return (
    <>
      <TextFieldSpecimen />
      <SearchFieldSpecimen />
      <SelectFieldSpecimen />
      <CheckboxSpecimen />
      <SegmentedControlSpecimen />
      <DateFieldSpecimen />
      <TimeZoneFieldSpecimen />
    </>
  );
}

function TextFieldSpecimen() {
  const [city, setCity] = useState("");
  return (
    <Specimen
      api="label · size: small | medium | large · required · hideLabel · error · disabled · native text input props"
      description="Its font, height, border, and focus surface match SearchField and SelectField. An error marks the field invalid and says how to fix it."
      id="text-field"
      title="TextField"
    >
      <div className={styles.specimenCases}>
        <SpecimenCase id="text-field-sizes">
          <div className={controls.fields}>
            <TextField defaultValue="Alex" label="Nickname" size="small" />
            <TextField defaultValue="Alex Morgan" label="Preferred name" />
            <TextField
              defaultValue="Alexandra Morgan"
              label="Full name"
              size="large"
            />
          </div>
        </SpecimenCase>
        <SpecimenCase id="text-field-states">
          <div className={controls.fields}>
            <TextField label="Empty text field" placeholder="Add a name" />
            <TextField
              defaultValue="A moment worth keeping"
              label="Title"
              required
            />
            <TextField
              disabled
              label="Disabled text field"
              placeholder="Unavailable"
            />
            <TextField
              error={city.trim() ? undefined : "Add a city before saving."}
              label="City"
              onChange={(event) => setCity(event.target.value)}
              value={city}
            />
          </div>
        </SpecimenCase>
      </div>
    </Specimen>
  );
}

function SearchFieldSpecimen() {
  const [query, setQuery] = useState("");
  const [message, setMessage] = useState(
    "Type a query to try this local-only preview.",
  );
  return (
    <Specimen
      api="label · hideLabel · size: small | medium | large · trailing · disabled · native input props"
      description="One focus surface for the icon and text. The search action stays composable, so each feature can choose its own submit behavior."
      id="search-field"
      title="SearchField"
    >
      <div className={styles.specimenCases}>
        <SpecimenCase id="search-field-sizes">
          <div className={controls.stack}>
            <SearchField
              label="Compact search"
              placeholder="Search your Entries"
              size="small"
            />
            <form
              className={styles.searchFieldDemo}
              onSubmit={(event) => {
                event.preventDefault();
                setMessage(
                  query.trim()
                    ? `Demo search: ${query.trim()}. No request was sent.`
                    : "Enter a search term first.",
                );
              }}
            >
              <SearchField
                label="Search Locations"
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Search for an address"
                value={query}
              />
              <Button type="submit" variant="secondary">
                Search
              </Button>
            </form>
            <SearchField
              label="Search Library"
              placeholder="A phrase, date, or question about your life..."
              size="large"
            />
          </div>
        </SpecimenCase>
        <SpecimenCase id="search-field-hidden-label">
          <div className={controls.stack}>
            <SearchField
              hideLabel
              label="Search MemoTrail"
              placeholder="Search Entries or go somewhere..."
              size="large"
              trailing={
                <kbd aria-hidden="true" className={controls.key}>
                  esc
                </kbd>
              }
            />
          </div>
        </SpecimenCase>
        <SpecimenCase id="search-field-disabled">
          <div className={controls.fields}>
            <SearchField
              disabled
              label="Disabled search"
              placeholder="Search unavailable"
            />
          </div>
        </SpecimenCase>
      </div>
      <p className={styles.stateNote} role="status">
        {message}
      </p>
    </Specimen>
  );
}

function SelectFieldSpecimen() {
  return (
    <Specimen
      api="label · size: small | medium | large · required · hideLabel · disabled · option and optgroup children"
      description="A labeled native select with the same surface and focus treatment as SearchField. Optgroups title runs of options."
      title="SelectField"
    >
      <div className={styles.specimenCases}>
        <SpecimenCase id="select-field-sizes">
          <div className={controls.fields}>
            <SelectField defaultValue="newest" label="Sort by" size="small">
              <option value="newest">Newest first</option>
              <option value="oldest">Oldest first</option>
            </SelectField>
            <SelectField defaultValue="all" label="Show records">
              <option value="all">All records</option>
              <option value="entries">Entries</option>
              <option value="chapters">Chapters</option>
            </SelectField>
            <SelectField
              defaultValue="timeline"
              label="Default view"
              size="large"
            >
              <option value="dashboard">Dashboard</option>
              <option value="timeline">Timeline</option>
              <option value="library">Library</option>
            </SelectField>
          </div>
        </SpecimenCase>
        <SpecimenCase id="select-field-groups">
          <div className={controls.fields}>
            <SelectField defaultValue="all" label="Record" required>
              <option value="all">All records</option>
              <optgroup label="Records">
                <option value="entries">Entries</option>
                <option value="chapters">Chapters</option>
              </optgroup>
              <optgroup label="Marks">
                <option value="first-times">First Times</option>
                <option value="favorites">Favorites</option>
              </optgroup>
            </SelectField>
          </div>
        </SpecimenCase>
        <SpecimenCase id="select-field-disabled">
          <div className={controls.fields}>
            <SelectField disabled label="Unavailable filter" size="small">
              <option>Unavailable</option>
            </SelectField>
          </div>
        </SpecimenCase>
      </div>
    </Specimen>
  );
}

const themeOptions = [
  { label: "System", value: "system" },
  { label: "Light", value: "light" },
  { label: "Dark", value: "dark" },
] as const;

const scaleOptions = [
  { label: "Years", value: "years" },
  { label: "Months", value: "months" },
] as const;

function SegmentedControlSpecimen() {
  const [theme, setTheme] = useState<string>("system");
  const [scale, setScale] = useState<string>("years");
  return (
    <Specimen
      api="label · options · value · onChange · name · disabled"
      description="A fieldset of radio inputs, so the arrow keys move the selection. The legend is visually hidden; the setting's label sits beside it."
      id="segmented-control"
      title="SegmentedControl"
    >
      <div className={styles.specimenCases}>
        <SpecimenCase id="segmented-control-states">
          <div className={styles.checkboxColumn}>
            <SegmentedControl
              label="Theme"
              onChange={setTheme}
              options={themeOptions}
              value={theme}
            />
            <SegmentedControl
              label="Timeline scale"
              onChange={setScale}
              options={scaleOptions}
              value={scale}
            />
            <SegmentedControl
              disabled
              label="Theme, disabled"
              onChange={() => undefined}
              options={themeOptions}
              value="light"
            />
          </div>
        </SpecimenCase>
      </div>
    </Specimen>
  );
}

function CheckboxSpecimen() {
  const [reminders, setReminders] = useState(false);
  const [submitted, setSubmitted] = useState("Nothing submitted yet.");
  return (
    <Specimen
      api="label · description · size: small | medium · disabled · native checkbox props (name, value, defaultChecked, required)"
      description="A native checkbox, so it submits with its form like any other. The label names it; the description is read after it."
      id="checkbox"
      title="Checkbox"
    >
      <div className={styles.specimenCases}>
        <SpecimenCase id="checkbox-sizes">
          <div className={styles.checkboxGrid}>
            <div className={styles.checkboxColumn}>
              <Checkbox label="Unchecked" />
              <Checkbox
                defaultChecked
                description="Shown on the Timeline"
                label="Checked"
              />
            </div>
            <div className={styles.checkboxColumn}>
              <Checkbox label="Small unchecked" size="small" />
              <Checkbox
                defaultChecked
                description="Still going on"
                label="Small checked"
                size="small"
              />
            </div>
          </div>
        </SpecimenCase>
        <SpecimenCase id="checkbox-states">
          <div className={styles.checkboxGrid}>
            <div className={styles.checkboxColumn}>
              <Checkbox
                checked={reminders}
                description="Controlled by this page"
                label="Remind me"
                onChange={(event) => setReminders(event.target.checked)}
              />
              <Checkbox
                description="A longer explanation wraps below the label until it needs another line, and never runs past its container."
                label="With description"
              />
            </div>
            <div className={styles.checkboxColumn}>
              <Checkbox disabled label="Disabled" />
              <Checkbox
                defaultChecked
                description="Cannot change"
                disabled
                label="Disabled checked"
              />
            </div>
          </div>
        </SpecimenCase>
      </div>
      <form
        className={styles.checkboxForm}
        onSubmit={(event) => {
          event.preventDefault();
          const data = new FormData(event.currentTarget);
          setSubmitted(
            `Submitted: ${JSON.stringify(
              Object.fromEntries(data.entries()),
            )}. No request was sent.`,
          );
        }}
      >
        <Checkbox
          defaultChecked
          label="Include photos"
          name="photos"
          value="yes"
        />
        <Checkbox label="Include Trash" name="trash" value="yes" />
        <Button type="submit" variant="secondary">
          Submit form
        </Button>
      </form>
      <p className={styles.stateNote} role="status">
        {reminders ? "Remind me is on. " : "Remind me is off. "}
        {submitted}
      </p>
    </Specimen>
  );
}

function DateFieldSpecimen() {
  const [date, setDate] = useState("2026-09-17");
  const [month, setMonth] = useState("2026-09");
  const [year, setYear] = useState("2026");
  const [dateTime, setDateTime] = useState("2026-09-17T14:30");
  const [from, setFrom] = useState("2026-09-01");
  const [start, setStart] = useState("2026-09-17");
  const [birthDate, setBirthDate] = useState("1990-04-12");
  const [emptyDate, setEmptyDate] = useState("");
  const [dueDate, setDueDate] = useState("");
  const [pickedDate, setPickedDate] = useState("");
  return (
    <Specimen
      api="granularity: day | month | year · size: small | medium | large · includeTime · required · editable · hideLabel · disabled"
      description="Date values, time controls, and calendar text use the shared form typography."
      title="DatePickerField"
    >
      <div className={styles.specimenCases}>
        <SpecimenCase id="date-field-precision">
          <div className={controls.fields}>
            <DatePickerField
              label="Filled date"
              onChange={setDate}
              value={date}
            />
            <DatePickerField
              granularity="month"
              label="Month precision"
              onChange={setMonth}
              value={month}
            />
            <DatePickerField
              granularity="year"
              label="Year precision"
              onChange={setYear}
              value={year}
            />
          </div>
        </SpecimenCase>
        <SpecimenCase id="date-field-with-time">
          <div className={controls.fields}>
            <DatePickerField
              includeTime
              label="Exact date and time"
              onChange={setDateTime}
              value={dateTime}
            />
          </div>
        </SpecimenCase>
        <SpecimenCase id="date-field-sizes">
          <div className={controls.fields}>
            <DatePickerField
              label="From"
              onChange={setFrom}
              size="small"
              value={from}
            />
            <DatePickerField
              label="Start date"
              onChange={setStart}
              value={start}
            />
            <DatePickerField
              label="Birth date"
              onChange={setBirthDate}
              size="large"
              value={birthDate}
            />
          </div>
        </SpecimenCase>
        <SpecimenCase id="date-field-states">
          <div className={controls.fields}>
            <DatePickerField
              label="Empty date"
              onChange={setEmptyDate}
              value={emptyDate}
            />
            <DatePickerField
              label="Due date"
              onChange={setDueDate}
              required
              value={dueDate}
            />
            <DatePickerField
              disabled
              label="Disabled"
              onChange={() => undefined}
              value="2026-09-17"
            />
            <DatePickerField
              editable={false}
              label="Picker only"
              onChange={setPickedDate}
              value={pickedDate}
            />
          </div>
        </SpecimenCase>
      </div>
    </Specimen>
  );
}

function TimeZoneFieldSpecimen() {
  const [timezone, setTimezone] = useState("America/Los_Angeles");
  return (
    <Specimen
      api="ariaLabel · value · referenceDate · disabled · className; the caller draws the label"
      description="Offsets follow the reference date, so daylight-saving time shows the offset that applied then."
      title="TimezoneSelect"
    >
      <div className={styles.specimenCases}>
        <SpecimenCase id="time-zone-field-offsets">
          <div className={controls.fields}>
            {(
              [
                ["Default time zone", "2026-01-15", "Winter offset"],
                ["Same zone in summer", "2026-07-15", "Summer offset"],
              ] as const
            ).map(([label, referenceDate, note]) => (
              <label className={controls.timeZone} key={label}>
                <span>
                  {label}
                  <small>{note}</small>
                </span>
                <TimezoneSelect
                  ariaLabel={label}
                  onChange={(event) => setTimezone(event.target.value)}
                  referenceDate={referenceDate}
                  value={timezone}
                />
              </label>
            ))}
          </div>
        </SpecimenCase>
      </div>
    </Specimen>
  );
}
