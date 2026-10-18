"use client";

import { DatePicker, type DateValue } from "@ark-ui/react/date-picker";
import { Popover } from "@ark-ui/react/popover";
import { Portal } from "@ark-ui/react/portal";
import { parseDate, type CalendarDate } from "@internationalized/date";
import { useEffect, useId, useRef, useState, type RefObject } from "react";
import { Icon } from "@/components/icon";
import {
  dateFieldDefaults,
  type DateFieldGranularity,
  type DateFieldSize,
} from "@/generated/design-system";
import { useOverlayContainer } from "./overlay-container";
import styles from "./date-fields.module.css";

export type DatePickerGranularity = DateFieldGranularity;
export type DatePickerFieldSize = DateFieldSize;
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
  name?: string;
  defaultValue?: string;
  value?: string;
  onChange?: (value: string) => void;
  portalContainer?: RefObject<HTMLElement | null>;
};

/**
 * A labeled, optional calendar value at day, month, or year precision, with an optional time.
 * Specified in packages/design-system/components/date-field.yaml.
 */
export function DatePickerField({
  disabled = false,
  editable = dateFieldDefaults.editable,
  granularity = dateFieldDefaults.granularity,
  label,
  hideLabel = dateFieldDefaults.hideLabel,
  includeTime = dateFieldDefaults.includeTime,
  initialView,
  maxValue,
  required = dateFieldDefaults.required,
  size = dateFieldDefaults.size,
  name,
  defaultValue = "",
  value: controlledValue,
  onChange: onValueChange,
  portalContainer: explicitPortalContainer,
}: DatePickerFieldProps) {
  const inheritedPortalContainer = useOverlayContainer();
  const portalContainer = explicitPortalContainer ?? inheritedPortalContainer;
  const [localValue, setLocalValue] = useState(defaultValue);
  const value = controlledValue ?? localValue;
  const inputRef = useRef<HTMLInputElement>(null);
  // Held in state, since the picker mounts its positioner after it opens.
  const [calendar, setCalendar] = useState<HTMLDivElement | null>(null);
  function onChange(nextValue: string) {
    if (controlledValue === undefined) setLocalValue(nextValue);
    onValueChange?.(nextValue);
  }
  const pickerId = useId();
  const [pickerOpen, setPickerOpen] = useState(false);
  useTopLayer(calendar, pickerOpen);
  const dateText = includeTime ? datePart(value) : value;
  const timeText = includeTime ? timePart(value) : "";
  const selected = calendarDate(dateText, granularity);
  const maximum = maxValue ? calendarDate(maxValue, "day") : null;

  // Named fields replace native GET/form controls. Domain editors without a
  // name retain their existing submit validation and contextual error messages.
  useEffect(() => {
    const invalid = Boolean(
      name && dateText && !calendarDate(dateText, granularity),
    );
    inputRef.current?.setCustomValidity(invalid ? "Enter a valid date." : "");
  }, [dateText, granularity, name]);

  useEffect(() => {
    if (controlledValue !== undefined) return;
    const form = inputRef.current?.form;
    const reset = () => setLocalValue(defaultValue);
    form?.addEventListener("reset", reset);
    return () => form?.removeEventListener("reset", reset);
  }, [controlledValue, defaultValue]);

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
    <div
      className={styles.datePickerField}
      data-date-picker-field
      data-granularity={granularity}
      data-size={size}
      data-ui-date-field
      data-ui-field
    >
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
            ref={inputRef}
            aria-haspopup={!editable ? "dialog" : undefined}
            aria-label={label}
            autoComplete="off"
            data-picker-only={!editable || undefined}
            disabled={disabled}
            inputMode="numeric"
            name={includeTime ? undefined : name}
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
          {includeTime && name ? (
            <input
              disabled={disabled}
              name={name}
              type="hidden"
              value={value}
            />
          ) : null}
          {includeTime ? (
            <TimePicker
              portalContainer={portalContainer}
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

        <Portal container={portalContainer}>
          <DatePicker.Positioner
            className={styles.datePickerPositioner}
            popover="manual"
            ref={setCalendar}
          >
            <DatePicker.Content
              className={styles.datePickerContent}
              data-escape-layer="calendar"
            >
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
  portalContainer,
}: {
  disabled: boolean;
  label: string;
  value: string;
  onChange: (value: string) => void;
  portalContainer?: RefObject<HTMLElement | null>;
}) {
  const parts = timeParts(value);
  const title = `Choose ${label.toLowerCase()} time`;
  const [positioner, setPositioner] = useState<HTMLDivElement | null>(null);
  const [open, setOpen] = useState(false);
  useTopLayer(positioner, open);

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
      onOpenChange={(details) => setOpen(details.open)}
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
      <Portal container={portalContainer}>
        <Popover.Positioner
          className={styles.timePickerPositioner}
          popover="manual"
          ref={setPositioner}
        >
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

/**
 * Shows an open picker in the top layer, so a scrolling or translucent
 * container, such as Quick Capture's native dialog, cannot clip it. The
 * picker stays in that container's tree, so the container keeps its focus and
 * theme.
 */
function useTopLayer(element: HTMLElement | null, open: boolean) {
  useEffect(() => {
    if (!open || !element?.isConnected) return;
    if (!element.matches(":popover-open")) element.showPopover();
    return () => {
      if (element.isConnected && element.matches(":popover-open"))
        element.hidePopover();
    };
  }, [element, open]);
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
