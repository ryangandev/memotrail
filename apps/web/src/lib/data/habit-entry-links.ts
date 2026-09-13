export type HabitEntryChoice = {
  id: string;
  title: string | null;
  excerpt: string;
  is_deleted: boolean;
};
export type HabitEntryChoices = {
  items: HabitEntryChoice[];
  selected: HabitEntryChoice | null;
  total_count: number;
};
export function habitEntryTitle(entry: HabitEntryChoice) {
  return entry.title?.trim() || entry.excerpt.trim() || "Untitled Entry";
}
