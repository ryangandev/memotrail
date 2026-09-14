"use client";

import { DatePicker, type DateValue } from "@ark-ui/react/date-picker";
import { Popover } from "@ark-ui/react/popover";
import { Portal } from "@ark-ui/react/portal";
import { parseDate, type CalendarDate } from "@internationalized/date";
import { useId, useState } from "react";
import { Icon } from "@/components/icon";
import styles from "@/app/page.module.css";

export type DatePickerGranularity = "day" | "month" | "year";
export type DatePickerFieldSize = "small" | "medium" | "large";
export type DatePickerFieldProps = {
  disabled?: boolean;
  editable?: boolean;
  granularity?: DatePickerGranularity;
  label: string;
  hideLabel?: boolean;
  includeTime?: boolean;
  initialView?: DatePickerGranularity;
  maxValue?: string;
  required?: boolean;
  size?: DatePickerFieldSize;
  value: string;
  onChange: (value: string) => void;
};

export function DatePickerField({
  disabled = false,
  editable = true,
  granularity = "day",
  label,
  hideLabel = false,
  includeTime = false,
  initialView,
  maxValue,
  required = false,
  size = "medium",
  value,
  onChange,
}: DatePickerFieldProps) {
  const pickerId = useId();
  const [pickerOpen, setPickerOpen] = useState(false);
  const dateText = includeTime ? datePart(value) : value;
  const timeText = includeTime ? timePart(value) : "";
  const selected = calendarDate(dateText, granularity);
  const maximum = maxValue ? calendarDate(maxValue, "day") : null;

  function changeDate(nextDate: string) {
    onChange(includeTime && timeText ? `${nextDate}T${timeText}` : nextDate);
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
    <div className={styles.datePickerField}>
      {hideLabel ? null : (
        <span>
          {label}
          {required ? (
            <span aria-hidden="true" className={styles.requiredMark}>
              *
            </span>
          ) : null}
        </span>
      )}
      <DatePicker.Root
        closeOnSelect
        defaultView={initialView ?? granularity}
        disabled={disabled}
        id={pickerId}
        max={maximum ?? undefined}
        maxView="year"
        minView={granularity}
        onOpenChange={(details) => setPickerOpen(details.open)}
        onValueChange={(details) => {
          const next = details.value[0];
          if (next) changeDate(storedDate(next, granularity));
        }}
        positioning={{ placement: "bottom-start", strategy: "fixed" }}
        unmountOnExit
        open={pickerOpen}
        value={selected ? [selected] : []}
      >
        <DatePicker.Control
          className={styles.datePickerControl}
          data-size={size}
        >
          <DatePicker.Trigger
            aria-label={`Choose ${label.toLowerCase()}`}
            className={styles.datePickerTrigger}
          >
            <Icon name="calendar" size={17} />
          </DatePicker.Trigger>
          <input
            aria-haspopup={!editable ? "dialog" : undefined}
            aria-label={label}
            autoComplete="off"
            data-picker-only={!editable || undefined}
            disabled={disabled}
            inputMode="numeric"
            onChange={
              editable
                ? (event) =>
                    changeDate(
                      formatNumericDate(event.target.value, granularity),
                    )
                : undefined
            }
            onClick={!editable ? () => setPickerOpen(true) : undefined}
            onKeyDown={
              !editable
                ? (event) => {
                    if (
                      event.key === "Enter" ||
                      event.key === " " ||
                      event.key === "ArrowDown"
                    ) {
                      event.preventDefault();
                      setPickerOpen(true);
                    }
                  }
                : (event) => {
                    if (
                      event.key.length === 1 &&
                      !/\d/.test(event.key) &&
                      !event.altKey &&
                      !event.ctrlKey &&
                      !event.metaKey
                    ) {
                      event.preventDefault();
                    }
                  }
            }
            placeholder={datePlaceholder(granularity)}
            readOnly={!editable}
            required={required}
            type="text"
            value={dateText}
          />
          {includeTime ? (
            <TimePicker
              disabled={disabled}
              label={label}
              onChange={changeTime}
              value={timeText}
            />
          ) : null}
          <button
            aria-label={`Clear ${label.toLowerCase()}`}
            className={styles.datePickerClear}
            data-empty={!value || undefined}
            disabled={disabled || !value}
            onClick={() => onChange("")}
            tabIndex={value ? undefined : -1}
            type="button"
          >
            <Icon name="close" size={16} />
          </button>
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
    }
    onChange(next.hour && next.minute ? `${next.hour}:${next.minute}` : "");
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
          <Popover.Content className={styles.timePickerContent}>
            <Popover.Title>{title}</Popover.Title>
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
                options={minutes}
                value={parts.minute}
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
      <DatePicker.PrevTrigger aria-label="Previous period">
        ‹
      </DatePicker.PrevTrigger>
      <DatePicker.ViewTrigger>
        <DatePicker.RangeText />
      </DatePicker.ViewTrigger>
      <DatePicker.NextTrigger aria-label="Next period">
        ›
      </DatePicker.NextTrigger>
    </DatePicker.ViewControl>
  );
}

function calendarDate(
  value: string,
  granularity: DatePickerGranularity,
): CalendarDate | null {
  const normalized =
    granularity === "year"
      ? /^\d{4}$/.test(value)
        ? `${value}-01-01`
        : null
      : granularity === "month"
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

function storedDate(date: DateValue, granularity: DatePickerGranularity) {
  const value = date.toString();
  if (granularity === "year") return value.slice(0, 4);
  if (granularity === "month") return value.slice(0, 7);
  return value.slice(0, 10);
}

function datePart(value: string) {
  return value.includes("T") ? value.slice(0, value.indexOf("T")) : value;
}

function timePart(value: string) {
  return value.includes("T") ? value.slice(value.indexOf("T") + 1) : "";
}

function timeParts(value: string) {
  const [hour = "", minute = ""] = value.split(":");
  return {
    hour: /^\d{2}$/.test(hour) ? hour : "",
    minute: /^\d{2}$/.test(minute) ? minute : "",
  };
}

function timeDisplay(parts: ReturnType<typeof timeParts>) {
  if (!parts.hour || !parts.minute) return "Time";
  return `${parts.hour}:${parts.minute}`;
}

function datePlaceholder(granularity: DatePickerGranularity) {
  if (granularity === "year") return "YYYY";
  if (granularity === "month") return "YYYY-MM";
  return "YYYY-MM-DD";
}

export function formatNumericDate(
  value: string,
  granularity: DatePickerGranularity,
) {
  const maximumDigits =
    granularity === "year" ? 4 : granularity === "month" ? 6 : 8;
  const digits = value.replace(/\D/g, "").slice(0, maximumDigits);
  if (granularity === "year" || digits.length <= 4) return digits;
  if (granularity === "month" || digits.length <= 6)
    return `${digits.slice(0, 4)}-${digits.slice(4)}`;
  return `${digits.slice(0, 4)}-${digits.slice(4, 6)}-${digits.slice(6)}`;
}

const hours = Array.from({ length: 24 }, (_, index) =>
  String(index).padStart(2, "0"),
);
const minutes = Array.from({ length: 60 }, (_, index) =>
  String(index).padStart(2, "0"),
);
