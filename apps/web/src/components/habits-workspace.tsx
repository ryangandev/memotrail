"use client";

import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type FormEvent,
  type ReactNode,
} from "react";
import { useRouter } from "next/navigation";
import {
  recordHabitOccurrence,
  saveHabit,
  trashHabit,
  type HabitActionResult,
} from "@/app/habits/actions";
import styles from "@/app/habits/page.module.css";
import { Icon } from "@/components/icon";
import {
  calculateHabitBreakdown,
  calculateHabitYearStats,
  calendarGridPosition,
  type HabitBreakdownRow,
  type HabitCalendarDay,
} from "@/lib/data/habit-analytics";
import {
  habitNameLimit,
  habitNoteLimit,
  habitUnitLimit,
  parseHabitInput,
  parseHabitOccurrenceInput,
  type HabitCalendarStatus,
  type HabitInput,
  type HabitOccurrenceStatus,
  type HabitSchedule,
  type HabitTrackingMode,
} from "@/lib/data/habit-input";
import type {
  Habit,
  HabitsWorkspace as HabitsWorkspaceData,
} from "@/lib/data/habits";
import { habitsHref } from "@/lib/data/habits-request";

const weekdays = [
  { label: "Mon", value: 1 },
  { label: "Tue", value: 2 },
  { label: "Wed", value: 3 },
  { label: "Thu", value: 4 },
  { label: "Fri", value: 5 },
  { label: "Sat", value: 6 },
  { label: "Sun", value: 7 },
];

const calendarLegend: { label: string; status: HabitCalendarStatus }[] = [
  { label: "Completed", status: "completed" },
  { label: "Missed", status: "missed" },
  { label: "Skipped", status: "skipped" },
  { label: "Pending", status: "pending" },
  { label: "Not scheduled", status: "not_scheduled" },
];

export function HabitsWorkspace({
  hasExplicitDate,
  workspace,
}: {
  hasExplicitDate: boolean;
  workspace: HabitsWorkspaceData;
}) {
  const router = useRouter();
  const [habitEditor, setHabitEditor] = useState<Habit | null | undefined>();
  const [checkIn, setCheckIn] = useState<{
    day: HabitCalendarDay | null;
    habit: Habit;
    localDate: string;
  } | null>(null);
  const [quickResult, setQuickResult] = useState<HabitActionResult | null>(
    null,
  );
  const [quickSavingId, setQuickSavingId] = useState<string | null>(null);
  const selectedHabit =
    workspace.habits.find((habit) => habit.id === workspace.selectedHabitId) ??
    null;
  const completedCount = workspace.habits.filter(
    (habit) => habit.status === "completed",
  ).length;
  const pendingCount = workspace.habits.filter(
    (habit) => habit.status === "pending" || habit.status === "missed",
  ).length;

  useEffect(() => {
    if (hasExplicitDate) {
      return;
    }

    const localToday = todayValue();

    if (localToday !== workspace.referenceDate) {
      router.replace(
        habitsHref({
          date: localToday,
          habitId: workspace.selectedHabitId,
          year: Number(localToday.slice(0, 4)),
        }),
      );
    }
  }, [
    hasExplicitDate,
    router,
    workspace.referenceDate,
    workspace.selectedHabitId,
  ]);

  function selectDate(localDate: string) {
    router.push(
      habitsHref({
        date: localDate,
        habitId: workspace.selectedHabitId,
        year: workspace.selectedYear,
      }),
    );
  }

  function selectHabit(habit: Habit) {
    router.push(
      habitsHref({
        date: workspace.referenceDate,
        habitId: habit.id,
        year: workspace.selectedYear,
      }),
    );
  }

  async function quickComplete(habit: Habit) {
    if (habit.trackingMode === "measure") {
      setCheckIn({ day: null, habit, localDate: workspace.referenceDate });
      return;
    }

    const input = {
      expectedRevision: habit.occurrence?.revision ?? null,
      habitId: habit.id,
      localDate: workspace.referenceDate,
      measuredValue: "",
      note: habit.occurrence?.note ?? "",
      status: "completed" as const,
      trackingMode: habit.trackingMode,
    };
    const parsed = parseHabitOccurrenceInput(input);

    if (!parsed.success) {
      setQuickResult({ message: parsed.message, status: "error" });
      return;
    }

    setQuickSavingId(habit.id);
    setQuickResult(null);

    try {
      const result = await recordHabitOccurrence(input);
      setQuickResult(result);

      if (result.status === "saved") {
        router.refresh();
      }
    } catch {
      setQuickResult({
        message: "MemoTrail could not reach the server. Try again when online.",
        status: "error",
      });
    } finally {
      setQuickSavingId(null);
    }
  }

  return (
    <div className={styles.content}>
      <header className={styles.pageHeader}>
        <div>
          <p className={styles.eyebrow}>Small actions, kept honestly</p>
          <h1>Habits</h1>
          <p>
            Check in lightly today, then look back without turning your life
            into a scorecard.
          </p>
        </div>
        <button
          className={styles.addButton}
          onClick={() => setHabitEditor(null)}
          type="button"
        >
          <Icon name="plus" />
          <span>New Habit</span>
        </button>
      </header>

      <div className={styles.dayToolbar}>
        <div>
          <span>{friendlyDate(workspace.referenceDate)}</span>
          <small>
            {completedCount} complete · {pendingCount} open
          </small>
        </div>
        <label>
          <span>Check-in date</span>
          <input
            max={todayValue()}
            onChange={(event) => selectDate(event.target.value)}
            type="date"
            value={workspace.referenceDate}
          />
        </label>
        {workspace.referenceDate !== todayValue() ? (
          <button onClick={() => selectDate(todayValue())} type="button">
            Today
          </button>
        ) : null}
      </div>

      {quickResult ? (
        <p
          className={
            quickResult.status === "saved"
              ? styles.successMessage
              : styles.errorMessage
          }
          role="status"
        >
          {quickResult.message}
        </p>
      ) : null}

      {workspace.loadError ? (
        <Message title="Habits unavailable" message={workspace.loadError} />
      ) : workspace.habits.length === 0 ? (
        <div className={styles.emptyState}>
          <span>
            <Icon name="check" size={24} />
          </span>
          <strong>Start with one gentle rhythm</strong>
          <p>
            Add a Habit such as taking a supplement, reading, or drinking water.
            You can change its schedule later.
          </p>
          <button onClick={() => setHabitEditor(null)} type="button">
            Add your first Habit
          </button>
        </div>
      ) : (
        <>
          <section
            className={styles.todaySection}
            aria-labelledby="today-habits"
          >
            <header>
              <div>
                <p className={styles.sectionLabel}>Check in</p>
                <h2 id="today-habits">Your Habits</h2>
              </div>
              <span>{workspace.habits.length} active</span>
            </header>
            <div className={styles.habitList}>
              {workspace.habits.map((habit) => (
                <HabitCard
                  habit={habit}
                  isSelected={habit.id === workspace.selectedHabitId}
                  isSaving={quickSavingId === habit.id}
                  key={habit.id}
                  onCheckIn={() =>
                    setCheckIn({
                      day: null,
                      habit,
                      localDate: workspace.referenceDate,
                    })
                  }
                  onEdit={() => setHabitEditor(habit)}
                  onQuickComplete={() => void quickComplete(habit)}
                  onSelect={() => selectHabit(habit)}
                />
              ))}
            </div>
          </section>

          {selectedHabit ? (
            <HabitHistory
              calendar={workspace.calendar}
              calendarError={workspace.calendarError}
              habit={selectedHabit}
              onCheckIn={(day) =>
                setCheckIn({
                  day,
                  habit: selectedHabit,
                  localDate: day.localDate,
                })
              }
              onYearChange={(year) =>
                router.push(
                  habitsHref({
                    date: workspace.referenceDate,
                    habitId: selectedHabit.id,
                    year,
                  }),
                )
              }
              referenceDate={workspace.referenceDate}
              year={workspace.selectedYear}
            />
          ) : null}
        </>
      )}

      {habitEditor !== undefined ? (
        <HabitEditor
          habit={habitEditor}
          key={habitEditor?.id ?? "new-habit"}
          onClose={() => setHabitEditor(undefined)}
          referenceDate={workspace.referenceDate}
        />
      ) : null}

      {checkIn ? (
        <CheckInEditor
          day={checkIn.day}
          habit={checkIn.habit}
          key={`${checkIn.habit.id}:${checkIn.localDate}`}
          localDate={checkIn.localDate}
          onClose={() => setCheckIn(null)}
        />
      ) : null}
    </div>
  );
}

function HabitCard({
  habit,
  isSaving,
  isSelected,
  onCheckIn,
  onEdit,
  onQuickComplete,
  onSelect,
}: {
  habit: Habit;
  isSaving: boolean;
  isSelected: boolean;
  onCheckIn: () => void;
  onEdit: () => void;
  onQuickComplete: () => void;
  onSelect: () => void;
}) {
  const canCheckIn = habit.status !== "not_scheduled";
  const complete = habit.status === "completed";

  return (
    <article
      className={`${styles.habitCard} ${isSelected ? styles.selectedHabit : ""}`}
    >
      <button
        aria-label={`Show ${habit.name} history`}
        className={styles.habitIdentity}
        onClick={onSelect}
        type="button"
      >
        <span className={`${styles.statusMark} ${statusClass(habit.status)}`}>
          {complete ? <Icon name="check" size={16} /> : null}
        </span>
        <span>
          <strong>{habit.name}</strong>
          <small>
            {scheduleLabel(habit.schedule)}
            {habit.trackingMode === "measure"
              ? ` · ${habit.targetValue} ${habit.measurementUnit}`
              : ""}
          </small>
        </span>
      </button>
      <div className={styles.habitStatus}>
        <strong>{statusLabel(habit.status)}</strong>
        {habit.occurrence?.measuredValue !== null &&
        habit.occurrence?.measuredValue !== undefined ? (
          <small>
            {habit.occurrence.measuredValue} {habit.measurementUnit}
          </small>
        ) : habit.occurrence?.note ? (
          <small>{habit.occurrence.note}</small>
        ) : null}
      </div>
      <div className={styles.cardActions}>
        <button
          aria-label={`Edit ${habit.name}`}
          onClick={onEdit}
          type="button"
        >
          Edit
        </button>
        {canCheckIn ? (
          <button onClick={onCheckIn} type="button">
            {habit.occurrence ? "Edit check-in" : "Details"}
          </button>
        ) : null}
        <button
          className={complete ? styles.completedButton : styles.completeButton}
          disabled={!canCheckIn || complete || isSaving}
          onClick={onQuickComplete}
          type="button"
        >
          {isSaving
            ? "Saving..."
            : complete
              ? "Completed"
              : habit.trackingMode === "measure"
                ? "Add value"
                : "Complete"}
        </button>
      </div>
    </article>
  );
}

function HabitHistory({
  calendar,
  calendarError,
  habit,
  onCheckIn,
  onYearChange,
  referenceDate,
  year,
}: {
  calendar: HabitCalendarDay[];
  calendarError: string | null;
  habit: Habit;
  onCheckIn: (day: HabitCalendarDay) => void;
  onYearChange: (year: number) => void;
  referenceDate: string;
  year: number;
}) {
  const stats = useMemo(
    () => calculateHabitYearStats(calendar, referenceDate),
    [calendar, referenceDate],
  );
  const firstDate = calendar[0]?.localDate ?? `${year}-01-01`;
  const monthMarkers = monthPositions(calendar, firstDate);

  return (
    <section className={styles.historySection} aria-labelledby="habit-history">
      <header className={styles.historyHeader}>
        <div>
          <p className={styles.sectionLabel}>Year in view</p>
          <h2 id="habit-history">{habit.name}</h2>
          <span>{scheduleLabel(habit.schedule)}</span>
        </div>
        <div className={styles.yearPicker}>
          <button
            aria-label={`Show ${year - 1}`}
            disabled={year <= 1900}
            onClick={() => onYearChange(year - 1)}
            type="button"
          >
            ←
          </button>
          <strong>{year}</strong>
          <button
            aria-label={`Show ${year + 1}`}
            disabled={year >= 2200}
            onClick={() => onYearChange(year + 1)}
            type="button"
          >
            →
          </button>
        </div>
      </header>

      {calendarError ? (
        <Message message={calendarError} title="History unavailable" />
      ) : (
        <>
          <div
            className={styles.statsGrid}
            aria-label={`${habit.name} statistics`}
          >
            <Stat
              label="Current streak"
              value={`${stats.currentStreak}`}
              suffix="checks"
            />
            <Stat
              label="Longest streak"
              value={`${stats.longestStreak}`}
              suffix="checks"
            />
            <Stat
              label="Completion"
              value={
                stats.completionRate === null
                  ? "-"
                  : `${Math.round(stats.completionRate * 100)}%`
              }
              suffix={`${stats.completed} done`}
            />
            <Stat
              label="Missed"
              value={`${stats.missed}`}
              suffix={`${stats.skipped} skipped`}
            />
          </div>

          <div className={styles.calendarSurface}>
            <div className={styles.calendarScroll}>
              <div className={styles.monthLabels}>
                {monthMarkers.map((month) => (
                  <span key={month.label} style={{ gridColumn: month.column }}>
                    {month.label}
                  </span>
                ))}
              </div>
              <div
                className={styles.yearCalendar}
                role="grid"
                aria-label={`${year} Habit calendar`}
              >
                {calendar.map((day) => {
                  const position = calendarGridPosition(
                    day.localDate,
                    firstDate,
                  );
                  const selectable = canCheckInDay(day, habit, referenceDate);

                  if (!position) {
                    return null;
                  }

                  return (
                    <button
                      aria-label={`${friendlyDate(day.localDate)}: ${statusLabel(day.status)}`}
                      className={`${styles.calendarDay} ${statusClass(day.status)}`}
                      disabled={!selectable}
                      key={day.localDate}
                      onClick={() => onCheckIn(day)}
                      role="gridcell"
                      style={{
                        gridColumn: position.column,
                        gridRow: position.row,
                      }}
                      title={`${day.localDate} · ${statusLabel(day.status)}`}
                      type="button"
                    />
                  );
                })}
              </div>
            </div>
            <div className={styles.calendarLegend} aria-label="Calendar legend">
              {calendarLegend.map((item) => (
                <span key={item.status}>
                  <i className={statusClass(item.status)} />
                  {item.label}
                </span>
              ))}
            </div>
          </div>
          <HabitBreakdown
            calendar={calendar}
            referenceDate={referenceDate}
            year={year}
            schedule={habit.schedule}
          />
        </>
      )}
    </section>
  );
}

function HabitBreakdown({
  calendar,
  referenceDate,
  year,
  schedule,
}: {
  calendar: HabitCalendarDay[];
  referenceDate: string;
  year: number;
  schedule: HabitSchedule;
}) {
  const summary = useMemo(
    () => calculateHabitBreakdown(calendar, referenceDate, year),
    [calendar, referenceDate, year],
  );
  return (
    <div className={styles.breakdown}>
      <p className={styles.breakdownGuidance}>
        {year} through {referenceDate}. Rate is Done ÷ (Done + Missed). Skipped,
        pending, unscheduled, and future days do not lower it.
        {schedule.kind === "weekly_target" &&
          " Weekly targets use recorded check-ins only; unrecorded days are not assigned missed weekdays."}
      </p>
      <div className={styles.breakdownPanels}>
        <section
          className={styles.breakdownPanel}
          aria-labelledby="monthly-summary"
        >
          <h3 id="monthly-summary">Monthly summary</h3>
          <BreakdownTable
            label="Monthly summary"
            firstColumn="Month"
            rows={summary.months}
          />
        </section>
        <section
          className={styles.breakdownPanel}
          aria-labelledby="weekday-patterns"
        >
          <h3 id="weekday-patterns">Weekday patterns</h3>
          <p className={styles.breakdownGuidance}>
            {summary.mostMisses === 0
              ? "No missed days in this view."
              : `Most misses: ${summary.mostMissedWeekdays.join(", ")} (${summary.mostMisses} each).`}
          </p>
          <BreakdownTable
            label="Weekday patterns"
            firstColumn="Weekday"
            rows={summary.weekdays}
          />
        </section>
      </div>
    </div>
  );
}

function BreakdownTable({
  label,
  firstColumn,
  rows,
}: {
  label: string;
  firstColumn: string;
  rows: HabitBreakdownRow[];
}) {
  return (
    <table className={styles.breakdownTable} aria-label={label}>
      <thead>
        <tr>
          {[firstColumn, "Done", "Missed", "Skipped", "Rate"].map((heading) => (
            <th key={heading} scope="col">
              {heading}
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {rows.map((row) => (
          <tr key={row.label}>
            <th scope="row">{row.label}</th>
            <td>{row.completed}</td>
            <td>{row.missed}</td>
            <td>{row.skipped}</td>
            <td>
              {row.completionRate === null
                ? "-"
                : `${Math.round(row.completionRate * 100)}%`}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function Stat({
  label,
  suffix,
  value,
}: {
  label: string;
  suffix: string;
  value: string;
}) {
  return (
    <div className={styles.statCard}>
      <span>{label}</span>
      <strong>{value}</strong>
      <small>{suffix}</small>
    </div>
  );
}

function HabitEditor({
  habit,
  onClose,
  referenceDate,
}: {
  habit: Habit | null;
  onClose: () => void;
  referenceDate: string;
}) {
  const router = useRouter();
  const nameRef = useRef<HTMLInputElement>(null);
  const initialSchedule = habit?.schedule ?? { kind: "daily" as const };
  const [endsOn, setEndsOn] = useState(habit?.endsOn ?? "");
  const [intervalDays, setIntervalDays] = useState(
    initialSchedule.kind === "interval"
      ? String(initialSchedule.every_days)
      : "2",
  );
  const [isPending, setIsPending] = useState(false);
  const [measurementUnit, setMeasurementUnit] = useState(
    habit?.measurementUnit ?? "",
  );
  const [name, setName] = useState(habit?.name ?? "");
  const [result, setResult] = useState<HabitActionResult | null>(null);
  const [scheduleKind, setScheduleKind] = useState<HabitSchedule["kind"]>(
    initialSchedule.kind,
  );
  const [startsOn, setStartsOn] = useState(habit?.startsOn ?? referenceDate);
  const [targetValue, setTargetValue] = useState(
    habit?.targetValue === null || habit?.targetValue === undefined
      ? ""
      : String(habit.targetValue),
  );
  const [trackingMode, setTrackingMode] = useState<HabitTrackingMode>(
    habit?.trackingMode ?? "check",
  );
  const [weekdaysValue, setWeekdaysValue] = useState<number[]>(
    initialSchedule.kind === "weekdays"
      ? initialSchedule.weekdays
      : [1, 2, 3, 4, 5],
  );
  const [weeklyTarget, setWeeklyTarget] = useState(
    initialSchedule.kind === "weekly_target"
      ? String(initialSchedule.target)
      : "3",
  );

  useEffect(() => {
    nameRef.current?.focus();
  }, []);

  function schedule(): HabitSchedule {
    if (scheduleKind === "weekdays") {
      return { kind: "weekdays", weekdays: weekdaysValue };
    }
    if (scheduleKind === "weekly_target") {
      return { kind: "weekly_target", target: Number(weeklyTarget) };
    }
    if (scheduleKind === "interval") {
      return { every_days: Number(intervalDays), kind: "interval" };
    }
    return { kind: "daily" };
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const input: HabitInput = {
      endsOn: endsOn || null,
      id: habit?.id ?? null,
      measurementUnit: trackingMode === "measure" ? measurementUnit : "",
      name,
      revision: habit?.revision ?? null,
      schedule: schedule(),
      startsOn,
      targetValue: trackingMode === "measure" ? targetValue : "",
      trackingMode,
    };
    const parsed = parseHabitInput(input);

    if (!parsed.success) {
      setResult({ message: parsed.message, status: "error" });
      return;
    }

    setIsPending(true);
    setResult(null);

    try {
      const nextResult = await saveHabit(input);

      if (nextResult.status === "created" || nextResult.status === "saved") {
        router.refresh();
        onClose();
        return;
      }

      setResult(nextResult);
    } catch {
      setResult({
        message: "MemoTrail could not reach the server. Try again when online.",
        status: "error",
      });
    } finally {
      setIsPending(false);
    }
  }

  async function handleTrash() {
    if (
      !habit ||
      !window.confirm(
        `Move “${habit.name}” to Trash? Its history will be preserved.`,
      )
    ) {
      return;
    }

    setIsPending(true);
    setResult(null);

    try {
      const nextResult = await trashHabit({
        id: habit.id,
        revision: habit.revision,
      });

      if (nextResult.status === "trashed") {
        router.refresh();
        onClose();
        return;
      }

      setResult(nextResult);
    } catch {
      setResult({
        message: "MemoTrail could not reach the server. Try again when online.",
        status: "error",
      });
    } finally {
      setIsPending(false);
    }
  }

  return (
    <Dialog label="habit-editor-title" onClose={onClose} pending={isPending}>
      <header className={styles.dialogHeader}>
        <div>
          <p>{habit ? "Edit Habit" : "New Habit"}</p>
          <h2 id="habit-editor-title">
            {habit?.name ?? "Build a gentle rhythm"}
          </h2>
        </div>
        <button
          aria-label="Close Habit editor"
          disabled={isPending}
          onClick={onClose}
          type="button"
        >
          ×
        </button>
      </header>

      <form onSubmit={handleSubmit}>
        <div className={styles.formGrid}>
          <label className={styles.fullField}>
            <span>Name</span>
            <input
              maxLength={habitNameLimit}
              onChange={(event) => setName(event.target.value)}
              placeholder="Take supplements"
              ref={nameRef}
              value={name}
            />
          </label>

          <fieldset className={`${styles.segmentedField} ${styles.fullField}`}>
            <legend>Tracking mode</legend>
            <div>
              <button
                aria-pressed={trackingMode === "check"}
                className={
                  trackingMode === "check" ? styles.segmentActive : undefined
                }
                onClick={() => setTrackingMode("check")}
                type="button"
              >
                Check
              </button>
              <button
                aria-pressed={trackingMode === "measure"}
                className={
                  trackingMode === "measure" ? styles.segmentActive : undefined
                }
                onClick={() => setTrackingMode("measure")}
                type="button"
              >
                Measure
              </button>
            </div>
            <p>
              {trackingMode === "check"
                ? "Record whether it happened."
                : "Record a number against a target."}
            </p>
          </fieldset>

          {trackingMode === "measure" ? (
            <>
              <label>
                <span>Target</span>
                <input
                  min="0.01"
                  onChange={(event) => setTargetValue(event.target.value)}
                  placeholder="8"
                  step="any"
                  type="number"
                  value={targetValue}
                />
              </label>
              <label>
                <span>Unit</span>
                <input
                  maxLength={habitUnitLimit}
                  onChange={(event) => setMeasurementUnit(event.target.value)}
                  placeholder="glasses"
                  value={measurementUnit}
                />
              </label>
            </>
          ) : null}

          <label className={styles.fullField}>
            <span>Schedule</span>
            <select
              onChange={(event) =>
                setScheduleKind(event.target.value as HabitSchedule["kind"])
              }
              value={scheduleKind}
            >
              <option value="daily">Every day</option>
              <option value="weekdays">Selected weekdays</option>
              <option value="weekly_target">Times per week</option>
              <option value="interval">Custom interval</option>
            </select>
          </label>

          {scheduleKind === "weekdays" ? (
            <fieldset className={`${styles.weekdayField} ${styles.fullField}`}>
              <legend>Active weekdays</legend>
              <div>
                {weekdays.map((weekday) => (
                  <button
                    aria-pressed={weekdaysValue.includes(weekday.value)}
                    className={
                      weekdaysValue.includes(weekday.value)
                        ? styles.weekdayActive
                        : undefined
                    }
                    key={weekday.value}
                    onClick={() =>
                      setWeekdaysValue(
                        toggleValue(weekdaysValue, weekday.value),
                      )
                    }
                    type="button"
                  >
                    {weekday.label}
                  </button>
                ))}
              </div>
            </fieldset>
          ) : null}

          {scheduleKind === "weekly_target" ? (
            <label className={styles.fullField}>
              <span>Times per week</span>
              <input
                max="7"
                min="1"
                onChange={(event) => setWeeklyTarget(event.target.value)}
                type="number"
                value={weeklyTarget}
              />
            </label>
          ) : null}

          {scheduleKind === "interval" ? (
            <label className={styles.fullField}>
              <span>Repeat every</span>
              <span className={styles.inlineInput}>
                <input
                  max="365"
                  min="1"
                  onChange={(event) => setIntervalDays(event.target.value)}
                  type="number"
                  value={intervalDays}
                />
                days
              </span>
            </label>
          ) : null}

          <label>
            <span>Start date</span>
            <input
              onChange={(event) => setStartsOn(event.target.value)}
              required
              type="date"
              value={startsOn}
            />
          </label>
          <label>
            <span>
              End date <small>Optional</small>
            </span>
            <input
              min={startsOn}
              onChange={(event) => setEndsOn(event.target.value)}
              type="date"
              value={endsOn}
            />
          </label>
        </div>

        {result ? (
          <p className={styles.formMessage} role="alert">
            {result.message}
          </p>
        ) : null}

        <DialogFooter
          destructiveLabel={habit ? "Move to Trash" : null}
          onCancel={onClose}
          onDestructive={() => void handleTrash()}
          pending={isPending}
          primaryLabel={habit ? "Save changes" : "Add Habit"}
        />
      </form>
    </Dialog>
  );
}

function CheckInEditor({
  day,
  habit,
  localDate,
  onClose,
}: {
  day: HabitCalendarDay | null;
  habit: Habit;
  localDate: string;
  onClose: () => void;
}) {
  const router = useRouter();
  const currentStatus = day
    ? (explicitOccurrenceStatus(day.status) ?? "completed")
    : (habit.occurrence?.status ?? "completed");
  const currentMeasurement = day
    ? day.measuredValue
    : habit.occurrence?.measuredValue;
  const currentNote = day ? day.note : habit.occurrence?.note;
  const currentRevision = day
    ? day.occurrenceRevision
    : (habit.occurrence?.revision ?? null);
  const [isPending, setIsPending] = useState(false);
  const [measuredValue, setMeasuredValue] = useState(
    currentMeasurement === null || currentMeasurement === undefined
      ? ""
      : String(currentMeasurement),
  );
  const [note, setNote] = useState(currentNote ?? "");
  const [result, setResult] = useState<HabitActionResult | null>(null);
  const [status, setStatus] = useState<HabitOccurrenceStatus>(currentStatus);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const input = {
      expectedRevision: currentRevision,
      habitId: habit.id,
      localDate,
      measuredValue: status === "completed" ? measuredValue : "",
      note,
      status,
      trackingMode: habit.trackingMode,
    };
    const parsed = parseHabitOccurrenceInput(input);

    if (!parsed.success) {
      setResult({ message: parsed.message, status: "error" });
      return;
    }

    setIsPending(true);
    setResult(null);

    try {
      const nextResult = await recordHabitOccurrence(input);

      if (nextResult.status === "saved") {
        router.refresh();
        onClose();
        return;
      }

      setResult(nextResult);
    } catch {
      setResult({
        message: "MemoTrail could not reach the server. Try again when online.",
        status: "error",
      });
    } finally {
      setIsPending(false);
    }
  }

  return (
    <Dialog label="check-in-editor-title" onClose={onClose} pending={isPending}>
      <header className={styles.dialogHeader}>
        <div>
          <p>{friendlyDate(localDate)}</p>
          <h2 id="check-in-editor-title">{habit.name}</h2>
        </div>
        <button
          aria-label="Close check-in editor"
          disabled={isPending}
          onClick={onClose}
          type="button"
        >
          ×
        </button>
      </header>
      <form onSubmit={handleSubmit}>
        <fieldset className={styles.statusPicker}>
          <legend>What happened?</legend>
          <div>
            {(["completed", "skipped", "missed"] as const).map((value) => (
              <button
                aria-pressed={status === value}
                className={status === value ? styles.segmentActive : undefined}
                key={value}
                onClick={() => setStatus(value)}
                type="button"
              >
                {statusLabel(value)}
              </button>
            ))}
          </div>
        </fieldset>

        <div className={styles.formGrid}>
          {habit.trackingMode === "measure" && status === "completed" ? (
            <label className={styles.fullField}>
              <span>
                Amount <small>{habit.measurementUnit}</small>
              </span>
              <input
                autoFocus
                min="0"
                onChange={(event) => setMeasuredValue(event.target.value)}
                placeholder={String(habit.targetValue ?? "")}
                step="any"
                type="number"
                value={measuredValue}
              />
            </label>
          ) : null}
          <label className={styles.fullField}>
            <span>
              Note <small>Optional</small>
            </span>
            <textarea
              autoFocus={habit.trackingMode === "check"}
              maxLength={habitNoteLimit}
              onChange={(event) => setNote(event.target.value)}
              placeholder="Anything worth remembering about this day?"
              rows={4}
              value={note}
            />
          </label>
        </div>

        {result ? (
          <p className={styles.formMessage} role="alert">
            {result.message}
          </p>
        ) : null}

        <DialogFooter
          destructiveLabel={null}
          onCancel={onClose}
          onDestructive={() => undefined}
          pending={isPending}
          primaryLabel={currentRevision ? "Update check-in" : "Save check-in"}
        />
      </form>
    </Dialog>
  );
}

function Dialog({
  children,
  label,
  onClose,
  pending,
}: {
  children: ReactNode;
  label: string;
  onClose: () => void;
  pending: boolean;
}) {
  useEffect(() => {
    function closeOnEscape(event: KeyboardEvent) {
      if (event.key === "Escape" && !pending) {
        onClose();
      }
    }
    window.addEventListener("keydown", closeOnEscape);
    return () => window.removeEventListener("keydown", closeOnEscape);
  }, [onClose, pending]);

  return (
    <div
      aria-labelledby={label}
      aria-modal="true"
      className={styles.dialogBackdrop}
      onMouseDown={(event) => {
        if (event.currentTarget === event.target && !pending) onClose();
      }}
      role="dialog"
    >
      <div className={styles.dialogPanel}>{children}</div>
    </div>
  );
}

function DialogFooter({
  destructiveLabel,
  onCancel,
  onDestructive,
  pending,
  primaryLabel,
}: {
  destructiveLabel: string | null;
  onCancel: () => void;
  onDestructive: () => void;
  pending: boolean;
  primaryLabel: string;
}) {
  return (
    <footer className={styles.dialogFooter}>
      <div>
        {destructiveLabel ? (
          <button
            className={styles.trashButton}
            disabled={pending}
            onClick={onDestructive}
            type="button"
          >
            {destructiveLabel}
          </button>
        ) : null}
      </div>
      <div>
        <button
          className={styles.cancelButton}
          disabled={pending}
          onClick={onCancel}
          type="button"
        >
          Cancel
        </button>
        <button className={styles.saveButton} disabled={pending} type="submit">
          {pending ? "Saving..." : primaryLabel}
        </button>
      </div>
    </footer>
  );
}

function Message({ message, title }: { message: string; title: string }) {
  return (
    <div className={styles.message} role="alert">
      <Icon name="check" size={23} />
      <div>
        <strong>{title}</strong>
        <p>{message}</p>
      </div>
    </div>
  );
}

function canCheckInDay(
  day: HabitCalendarDay,
  habit: Habit,
  referenceDate: string,
) {
  return (
    day.localDate <= referenceDate &&
    day.localDate >= habit.startsOn &&
    (!habit.endsOn || day.localDate <= habit.endsOn) &&
    (day.isScheduled || habit.schedule.kind === "weekly_target")
  );
}

function monthPositions(calendar: HabitCalendarDay[], firstDate: string) {
  const formatter = new Intl.DateTimeFormat("en-US", {
    month: "short",
    timeZone: "UTC",
  });

  return calendar
    .filter((day) => day.localDate.endsWith("-01"))
    .map((day) => ({
      column: calendarGridPosition(day.localDate, firstDate)?.column ?? 1,
      label: formatter.format(new Date(`${day.localDate}T12:00:00Z`)),
    }));
}

function statusClass(status: HabitCalendarStatus) {
  const classes: Record<HabitCalendarStatus, string> = {
    completed: styles.statusCompleted,
    missed: styles.statusMissed,
    not_scheduled: styles.statusNotScheduled,
    pending: styles.statusPending,
    skipped: styles.statusSkipped,
    upcoming: styles.statusUpcoming,
  };
  return classes[status];
}

function statusLabel(status: HabitCalendarStatus) {
  const labels: Record<HabitCalendarStatus, string> = {
    completed: "Completed",
    missed: "Missed",
    not_scheduled: "Not scheduled",
    pending: "Ready",
    skipped: "Skipped",
    upcoming: "Upcoming",
  };
  return labels[status];
}

function scheduleLabel(schedule: HabitSchedule) {
  if (schedule.kind === "daily") return "Every day";
  if (schedule.kind === "weekly_target")
    return `${schedule.target} times per week`;
  if (schedule.kind === "interval") return `Every ${schedule.every_days} days`;
  return schedule.weekdays
    .map((value) => weekdays.find((day) => day.value === value)?.label)
    .filter(Boolean)
    .join(", ");
}

function friendlyDate(value: string) {
  return new Intl.DateTimeFormat("en-US", {
    day: "numeric",
    month: "long",
    timeZone: "UTC",
    weekday: "long",
    year: "numeric",
  }).format(new Date(`${value}T12:00:00Z`));
}

function todayValue() {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
}

function toggleValue(values: number[], value: number) {
  return values.includes(value)
    ? values.filter((item) => item !== value)
    : [...values, value].sort((a, b) => a - b);
}

function explicitOccurrenceStatus(value: HabitCalendarStatus | undefined) {
  return value === "completed" || value === "missed" || value === "skipped"
    ? value
    : null;
}
