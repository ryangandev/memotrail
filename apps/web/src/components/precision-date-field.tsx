"use client";

import {
  DatePicker,
  type DateValue,
} from "@ark-ui/react/date-picker";
import { Popover } from "@ark-ui/react/popover";
import { Portal } from "@ark-ui/react/portal";
import { parseDate, type CalendarDate } from "@internationalized/date";
import { useId } from "react";
import { Icon } from "@/components/icon";
import type { OccurrencePrecision } from "@/lib/data/occurrence";
import styles from "@/app/page.module.css";

type CalendarPrecision = Exclude<OccurrencePrecision, "unknown">;

export function PrecisionDateField({
  disabled,
  label,
  hideLabel = false,
  precision,
  value,
  onChange,
}: {
  disabled: boolean;
  label: string;
  hideLabel?: boolean;
  precision: CalendarPrecision;
  value: string;
  onChange: (value: string) => void;
}) {
  const pickerId = useId();
  const view = precision === "year" ? "year" : precision === "month" ? "month" : "day";
  const dateText = precision === "exact" ? exactDate(value) : value;
  const timeText = precision === "exact" ? exactTime(value) : "";
  const selected = calendarDate(dateText, precision);

  function changeDate(nextDate: string) {
    onChange(
      precision === "exact" && timeText
        ? `${nextDate}T${timeText}`
        : nextDate,
    );
  }

  function changeTime(nextTime: string) {
    onChange(
      dateText
        ? `${dateText}${nextTime ? `T${nextTime}` : ""}`
        : nextTime
          ? `T${nextTime}`
          : "",
    );
  }

  return (
    <div className={styles.precisionDateField}>
      {hideLabel ? null : <span>{label}</span>}
      <DatePicker.Root
        closeOnSelect
        defaultView={view}
        disabled={disabled}
        id={pickerId}
        maxView={view === "day" ? "year" : view}
        minView={view}
        onValueChange={(details) => {
          const next = details.value[0];
          if (next) changeDate(storedDate(next, precision));
        }}
        positioning={{ placement: "bottom-start", strategy: "fixed" }}
        unmountOnExit
        value={selected ? [selected] : []}
      >
        <DatePicker.Control className={styles.datePickerControl}>
          <DatePicker.Trigger
            aria-label={`Choose ${label.toLowerCase()}`}
            className={styles.datePickerTrigger}
          >
            <Icon name="calendar" size={17} />
          </DatePicker.Trigger>
          <input
            aria-label={label}
            autoComplete="off"
            disabled={disabled}
            inputMode="numeric"
            maxLength={dateLength(precision)}
            onChange={(event) => changeDate(event.target.value)}
            placeholder={datePlaceholder(precision)}
            value={dateText}
          />
          {precision === "exact" ? (
            <TimePicker
              disabled={disabled}
              label={label}
              onChange={changeTime}
              value={timeText}
            />
          ) : null}
          {value ? (
            <button
              aria-label={`Clear ${label.toLowerCase()}`}
              className={styles.datePickerClear}
              disabled={disabled}
              onClick={() => onChange("")}
              type="button"
            >
              <span aria-hidden="true">×</span>
            </button>
          ) : null}
        </DatePicker.Control>

        <Portal>
          <DatePicker.Positioner className={styles.datePickerPositioner}>
            <DatePicker.Content className={styles.datePickerContent}>
              <DatePicker.Context>
                {(picker) => (
                  <>
                    <DatePicker.View view="day">
                      <CalendarHeader />
                      <DatePicker.Table className={styles.calendarTable}>
                        <DatePicker.TableHead>
                          <DatePicker.TableRow>
                            {picker.weekDays.map((weekDay) => (
                              <DatePicker.TableHeader key={weekDay.short}>
                                {weekDay.narrow}
                              </DatePicker.TableHeader>
                            ))}
                          </DatePicker.TableRow>
                        </DatePicker.TableHead>
                        <DatePicker.TableBody>
                          {picker.weeks.map((week) => (
                            <DatePicker.TableRow key={week[0].toString()}>
                              {week.map((day) => (
                                <DatePicker.TableCell
                                  key={day.toString()}
                                  value={day}
                                  visibleRange={picker.visibleRange}
                                >
                                  <DatePicker.TableCellTrigger
                                    className={styles.calendarCellTrigger}
                                  >
                                    {day.day}
                                  </DatePicker.TableCellTrigger>
                                </DatePicker.TableCell>
                              ))}
                            </DatePicker.TableRow>
                          ))}
                        </DatePicker.TableBody>
                      </DatePicker.Table>
                    </DatePicker.View>

                    <DatePicker.View view="month">
                      <CalendarHeader />
                      <DatePicker.Table
                        className={styles.calendarTable}
                        columns={4}
                      >
                        <DatePicker.TableBody>
                          {picker
                            .getMonthsGrid({ columns: 4, format: "short" })
                            .map((months) => (
                              <DatePicker.TableRow key={months[0].value}>
                                {months.map((month) => (
                                  <DatePicker.TableCell
                                    columns={4}
                                    disabled={month.disabled}
                                    key={month.value}
                                    value={month.value}
                                  >
                                    <DatePicker.TableCellTrigger
                                      className={styles.calendarCellTrigger}
                                    >
                                      {month.label}
                                    </DatePicker.TableCellTrigger>
                                  </DatePicker.TableCell>
                                ))}
                              </DatePicker.TableRow>
                            ))}
                        </DatePicker.TableBody>
                      </DatePicker.Table>
                    </DatePicker.View>

                    <DatePicker.View view="year">
                      <CalendarHeader />
                      <DatePicker.Table
                        className={styles.calendarTable}
                        columns={4}
                      >
                        <DatePicker.TableBody>
                          {picker.getYearsGrid({ columns: 4 }).map((years) => (
                            <DatePicker.TableRow key={years[0].value}>
                              {years.map((year) => (
                                <DatePicker.TableCell
                                  columns={4}
                                  disabled={year.disabled}
                                  key={year.value}
                                  value={year.value}
                                >
                                  <DatePicker.TableCellTrigger
                                    className={styles.calendarCellTrigger}
                                  >
                                    {year.label}
                                  </DatePicker.TableCellTrigger>
                                </DatePicker.TableCell>
                              ))}
                            </DatePicker.TableRow>
                          ))}
                        </DatePicker.TableBody>
                      </DatePicker.Table>
                    </DatePicker.View>
                  </>
                )}
              </DatePicker.Context>
            </DatePicker.Content>
          </DatePicker.Positioner>
        </Portal>
      </DatePicker.Root>
    </div>
  );
}

function TimePicker({
  disabled,
  label,
  value,
  onChange,
}: {
  disabled: boolean;
  label: string;
  value: string;
  onChange: (value: string) => void;
}) {
  const parts = timeParts(value);
  const title = `Choose ${label.toLowerCase()} time`;

  function change(part: keyof typeof parts, nextValue: string) {
    const next = { ...parts, [part]: nextValue };
    if (nextValue) {
      if (!next.hour) next.hour = "00";
      if (!next.minute) next.minute = "00";
      if (!next.second) next.second = "00";
    }
    onChange(
      next.hour && next.minute
        ? `${next.hour}:${next.minute}:${next.second || "00"}`
        : "",
    );
  }

  return (
    <Popover.Root
      positioning={{ placement: "bottom", strategy: "fixed" }}
      unmountOnExit
    >
      <Popover.Trigger
        aria-label={title}
        className={styles.timePickerTrigger}
        disabled={disabled}
      >
        <Icon name="clock" size={15} />
        <span>{timeDisplay(parts)}</span>
      </Popover.Trigger>
      <Portal>
        <Popover.Positioner className={styles.timePickerPositioner}>
          <Popover.Content
            aria-label={title}
            className={styles.timePickerContent}
          >
            <Popover.Title>Choose time</Popover.Title>
            <div className={styles.timePickerFields}>
              <TimeSelect
                label="Hour"
                onChange={(next) => change("hour", next)}
                options={hours}
                value={parts.hour}
              />
              <span aria-hidden="true">:</span>
              <TimeSelect
                label="Minute"
                onChange={(next) => change("minute", next)}
                options={minutesAndSeconds}
                value={parts.minute}
              />
              <span aria-hidden="true">:</span>
              <TimeSelect
                label="Second"
                onChange={(next) => change("second", next)}
                options={minutesAndSeconds}
                value={parts.second}
              />
            </div>
            <Popover.CloseTrigger
              aria-label="Done"
              className={styles.timePickerDone}
            >
              Done
            </Popover.CloseTrigger>
          </Popover.Content>
        </Popover.Positioner>
      </Portal>
    </Popover.Root>
  );
}

function TimeSelect({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: string;
  options: readonly string[];
  onChange: (value: string) => void;
}) {
  return (
    <label>
      <span>{label}</span>
      <select
        aria-label={label}
        onChange={(event) => onChange(event.target.value)}
        value={value}
      >
        <option value="">--</option>
        {options.map((option) => (
          <option key={option} value={option}>
            {option}
          </option>
        ))}
      </select>
    </label>
  );
}

function CalendarHeader() {
  return (
    <DatePicker.ViewControl className={styles.calendarHeader}>
      <DatePicker.PrevTrigger aria-label="Previous period">‹</DatePicker.PrevTrigger>
      <DatePicker.ViewTrigger>
        <DatePicker.RangeText />
      </DatePicker.ViewTrigger>
      <DatePicker.NextTrigger aria-label="Next period">›</DatePicker.NextTrigger>
    </DatePicker.ViewControl>
  );
}

function calendarDate(
  value: string,
  precision: CalendarPrecision,
): CalendarDate | null {
  const normalized =
    precision === "year"
      ? /^\d{4}$/.test(value)
        ? `${value}-01-01`
        : null
      : precision === "month"
        ? /^\d{4}-\d{2}$/.test(value)
          ? `${value}-01`
          : null
        : /^\d{4}-\d{2}-\d{2}$/.test(value)
          ? value
          : null;

  if (!normalized) return null;

  try {
    return parseDate(normalized);
  } catch {
    return null;
  }
}

function storedDate(date: DateValue, precision: CalendarPrecision) {
  const value = date.toString();
  if (precision === "year") return value.slice(0, 4);
  if (precision === "month") return value.slice(0, 7);
  return value.slice(0, 10);
}

function exactDate(value: string) {
  return value.includes("T") ? value.slice(0, value.indexOf("T")) : value;
}

function exactTime(value: string) {
  return value.includes("T") ? value.slice(value.indexOf("T") + 1) : "";
}

function timeParts(value: string) {
  const [hour = "", minute = "", second = ""] = value.split(":");
  return {
    hour: /^\d{2}$/.test(hour) ? hour : "",
    minute: /^\d{2}$/.test(minute) ? minute : "",
    second: /^\d{2}$/.test(second) ? second : "",
  };
}

function timeDisplay(parts: ReturnType<typeof timeParts>) {
  if (!parts.hour || !parts.minute) return "Time";
  return parts.second && parts.second !== "00"
    ? `${parts.hour}:${parts.minute}:${parts.second}`
    : `${parts.hour}:${parts.minute}`;
}

function dateLength(precision: CalendarPrecision) {
  if (precision === "year") return 4;
  if (precision === "month") return 7;
  return 10;
}

function datePlaceholder(precision: CalendarPrecision) {
  if (precision === "year") return "YYYY";
  if (precision === "month") return "YYYY-MM";
  return "YYYY-MM-DD";
}

const hours = Array.from({ length: 24 }, (_, index) =>
  String(index).padStart(2, "0"),
);
const minutesAndSeconds = Array.from({ length: 60 }, (_, index) =>
  String(index).padStart(2, "0"),
);
