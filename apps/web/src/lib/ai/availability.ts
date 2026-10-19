import type { AIRequestFeature } from "./contracts";

// Product availability, not provider configuration or a person's saved consent.
// Chapter and year reviews and Chapter suggestions are the only AI features offered.
// Every other feature stays paused until its use case and entry points are accepted.
export const AVAILABLE_AI_FEATURES: ReadonlySet<AIRequestFeature> =
  new Set<AIRequestFeature>(["review", "chapter_suggestion"]);
export const AI_PAUSED_MESSAGE =
  "This AI capability is paused while we rethink how it can help. Manual features remain available.";

export function aiFeatureAvailable(feature: AIRequestFeature | "connection") {
  return feature !== "connection" && AVAILABLE_AI_FEATURES.has(feature);
}
