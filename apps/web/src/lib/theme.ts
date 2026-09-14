export const THEME_COOKIE_NAME = "memotrail-theme";

export const themePreferences = ["system", "light", "dark"] as const;

export type ThemePreference = (typeof themePreferences)[number];

export function storedThemePreference(value: unknown): ThemePreference {
  return themePreferences.includes(value as ThemePreference)
    ? (value as ThemePreference)
    : "system";
}

export function explicitTheme(preference: ThemePreference) {
  return preference === "system" ? undefined : preference;
}
