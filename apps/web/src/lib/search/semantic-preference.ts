export type StoredSemanticSearchPreference =
  { available: false; enabled: true } | { available: true; enabled: boolean };

/**
 * Search by meaning is on unless the profile says otherwise. A profile without the
 * column belongs to a database that predates the feature, so the setting is hidden.
 */
export function storedSemanticSearchPreference(
  value: unknown,
): StoredSemanticSearchPreference {
  if (
    typeof value !== "object" ||
    value === null ||
    !("semantic_search_enabled" in value)
  ) {
    return { available: false, enabled: true };
  }

  return { available: true, enabled: value.semantic_search_enabled !== false };
}
