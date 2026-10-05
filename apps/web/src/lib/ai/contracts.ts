export const AI_MODEL = "claude-haiku-4-5-20251001";
export const aiFeatures = [
  "classification",
  "tagging",
  "search",
  "explore",
  "resurfacing",
  "photo_analysis",
] as const;
export type AIFeature = (typeof aiFeatures)[number];
export type AIPreferences = Record<AIFeature | "enabled", boolean> & {
  monthly_budget_micros: number;
  revision: number;
};
export type AIUsage = {
  id: string;
  feature: string;
  model: string;
  status: "reserved" | "completed" | "failed" | "uncertain";
  charged_micros: number;
  input_tokens: number | null;
  output_tokens: number | null;
  created_at: string;
};
export type AIWorkspace = {
  preferences: AIPreferences;
  month_charged_micros: number;
  recent_usage: AIUsage[];
};

export const defaultAIMonthlyBudgetMicros = 1_000_000;

export const simpleAIControls = [
  "enabled",
  "organizing",
  "photo_analysis",
] as const;
export type SimpleAIControl = (typeof simpleAIControls)[number];

export function simpleAIControlChecked(
  preferences: AIPreferences,
  control: SimpleAIControl,
) {
  if (control === "organizing") {
    return preferences.classification || preferences.tagging;
  }
  return preferences[control];
}

export function updateSimpleAIPreferences(
  preferences: AIPreferences,
  control: SimpleAIControl,
  checked: boolean,
): AIPreferences {
  const normalized = { ...preferences, resurfacing: false };

  if (control === "enabled") {
    return {
      ...normalized,
      enabled: checked,
      explore: checked ? true : normalized.explore,
      monthly_budget_micros:
        checked && normalized.monthly_budget_micros === 0
          ? defaultAIMonthlyBudgetMicros
          : normalized.monthly_budget_micros,
      search: checked ? true : normalized.search,
    };
  }

  if (control === "organizing") {
    return {
      ...normalized,
      classification: checked,
      tagging: checked,
    };
  }

  return { ...normalized, photo_analysis: checked };
}
export const featureLabels: Record<AIFeature, string> = {
  classification: "Title, Type, and date suggestions",
  tagging: "Tag suggestions",
  search: "Natural-language search",
  explore: "Explore with AI",
  resurfacing: "AI-assisted memory resurfacing",
  photo_analysis: "Photo analysis (separate opt-in)",
};
export function parseAIPreferences(value: unknown): AIPreferences | null {
  if (!value || typeof value !== "object") return null;
  const v = value as Record<string, unknown>;
  if (
    !["enabled", ...aiFeatures].every((k) => typeof v[k] === "boolean") ||
    !Number.isSafeInteger(v.revision) ||
    Number(v.revision) < 0 ||
    !Number.isSafeInteger(v.monthly_budget_micros) ||
    Number(v.monthly_budget_micros) < 0 ||
    Number(v.monthly_budget_micros) > 100_000_000
  )
    return null;
  return Object.fromEntries(
    ["enabled", ...aiFeatures, "revision", "monthly_budget_micros"].map((k) => [
      k,
      v[k],
    ]),
  ) as AIPreferences;
}
export function formatAICost(micros: number) {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
    maximumFractionDigits: 6,
  }).format(micros / 1_000_000);
}
export { requestOriginAllowed as aiOriginAllowed } from "@/lib/auth/origin";
