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
export const featureLabels: Record<AIFeature, string> = {
  classification: "Title, Type, Collection, and date suggestions",
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
export function aiOriginAllowed(
  request: Request,
  bearer: boolean,
  appURL?: string,
) {
  if (bearer) return true;
  const origin = request.headers.get("origin");
  // Next may normalize the internal hostname behind its development server or proxy.
  // The explicitly configured public URL remains the trusted browser origin.
  return origin === new URL(appURL || request.url).origin;
}
