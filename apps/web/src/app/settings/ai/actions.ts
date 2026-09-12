"use server";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { parseAIPreferences, type AIPreferences } from "@/lib/ai/contracts";
export async function saveAISettings(value: AIPreferences) {
  const preferences = parseAIPreferences(value);
  if (!preferences)
    return { error: "Choose a monthly budget between $0 and $100." };
  const context = await getAuthenticatedContext();
  if (!context) return { error: "Sign in again to change AI settings." };
  const { data, error } = await context.client.rpc("save_ai_preferences", {
    p_preferences: preferences,
    p_expected_revision: preferences.revision,
  });
  if (error) return { error: "Could not save AI settings. Try again." };
  if (!data)
    return {
      error: "Settings changed on another device. Reload before saving again.",
    };
  return { data };
}

export async function dismissAISuggestion(id: string) {
  if (!/^[0-9a-f-]{36}$/i.test(id)) return "Invalid suggestion.";
  const context = await getAuthenticatedContext();
  if (!context) return "Sign in again to dismiss suggestions.";
  const { data, error } = await context.client.rpc("dismiss_ai_suggestion", {
    p_id: id,
  });
  return error || !data
    ? "Could not dismiss these suggestions. Reopen the Entry and try again."
    : null;
}
