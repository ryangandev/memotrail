/**
 * What search by meaning is doing for one search, so Library can say why meaning results
 * are missing:
 * - `on`: meaning results were considered;
 * - `off`: the user turned it off in Settings;
 * - `unavailable`: it is on but the embedding service did not answer;
 * - `not_configured`: this deployment has no embedding service (or the merged search is
 *   not deployed yet), so search is keyword-only without any notice.
 */
export type SemanticSearchState =
  "not_configured" | "off" | "on" | "unavailable";

export type SemanticSearchStatus = {
  /** Active Entries not yet searchable by meaning. */
  pendingCount: number;
  state: SemanticSearchState;
};

export const KEYWORD_ONLY_STATUS: SemanticSearchStatus = {
  pendingCount: 0,
  state: "not_configured",
};
