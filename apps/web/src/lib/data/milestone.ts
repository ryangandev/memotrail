// A milestone puts an Entry on Timeline: a Moment or a Period, in the Work and study lane
// or the Other lane, and optionally a First Time. Homes and Vehicles have their own lanes
// and are on Timeline without one.
export const milestoneShapes = ["moment", "period"] as const;
export type MilestoneShape = (typeof milestoneShapes)[number];

export const milestoneLanes = ["work_study", "other"] as const;
export type MilestoneLane = (typeof milestoneLanes)[number];

export type Milestone = {
  isFirstTime: boolean;
  lane: MilestoneLane;
  shape: MilestoneShape;
};

export const timelineLanes = [
  "homes",
  "vehicles",
  "work_study",
  "other",
] as const;
export type TimelineLane = (typeof timelineLanes)[number];

export const timelineLaneLabels: Record<TimelineLane, string> = {
  homes: "Places lived",
  vehicles: "Vehicles",
  work_study: "Work and study",
  other: "Other milestones",
};

export function isMilestoneShape(value: unknown): value is MilestoneShape {
  return milestoneShapes.includes(value as MilestoneShape);
}

export function isMilestoneLane(value: unknown): value is MilestoneLane {
  return milestoneLanes.includes(value as MilestoneLane);
}

export function isTimelineLane(value: unknown): value is TimelineLane {
  return timelineLanes.includes(value as TimelineLane);
}

export function isMilestone(value: unknown): value is Milestone {
  if (typeof value !== "object" || value === null) return false;
  const milestone = value as Record<string, unknown>;
  return (
    isMilestoneShape(milestone.shape) &&
    isMilestoneLane(milestone.lane) &&
    typeof milestone.isFirstTime === "boolean"
  );
}

// Reads the `{shape, lane, is_first_time}` object the database returns.
export function milestoneFromRow(value: unknown): Milestone | null {
  if (typeof value !== "object" || value === null) return null;
  const row = value as Record<string, unknown>;
  if (
    !isMilestoneShape(row.shape) ||
    !isMilestoneLane(row.lane) ||
    typeof row.is_first_time !== "boolean"
  )
    return null;
  return { isFirstTime: row.is_first_time, lane: row.lane, shape: row.shape };
}

// The shape `save_entry` reads.
export function milestoneRow(milestone: Milestone | null) {
  return milestone
    ? {
        isFirstTime: milestone.isFirstTime,
        lane: milestone.lane,
        shape: milestone.shape,
      }
    : null;
}

export function milestoneLabel(
  milestone: Pick<Milestone, "isFirstTime" | "shape">,
) {
  if (milestone.isFirstTime) return "First Time";
  return milestone.shape === "period" ? "Period" : "Moment";
}
