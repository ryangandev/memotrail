import pageStyles from "@/app/settings/page.module.css";
import settingsFieldsStyles from "@/components/settings-fields.module.css";
import { PageHeader } from "@/components/page-header";
import { Button, ButtonLink } from "@/components/button";
import { cookies } from "next/headers";
import { signOut } from "@/app/auth/actions";
import { AppearanceSetting } from "@/components/appearance-setting";
import { BirthDateSetting } from "@/components/birth-date-setting";
import { TimezoneSetting } from "@/components/timezone-setting";
import { PageFrame } from "@/components/page-frame";
import { SectionHeader } from "@/components/section-header";
import { SettingRow } from "@/components/setting-row";
import { PreferredNameSetting } from "@/components/preferred-name-setting";
import { SemanticSearchSetting } from "@/components/semantic-search-setting";
import { ReviewsSetting } from "@/components/reviews-setting";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { loadReviewSettings } from "@/lib/data/reviews";
import {
  storedBirthDate,
  storedProfileTimezone,
} from "@/lib/data/profile-input";
import { semanticSearchConfigured } from "@/lib/search/embedding-client";
import { storedSemanticSearchPreference } from "@/lib/search/semantic-preference";
import { storedThemePreference, THEME_COOKIE_NAME } from "@/lib/theme";

export const dynamic = "force-dynamic";

export default async function SettingsPage() {
  const context = await getAuthenticatedContext();

  if (!context) return null;

  const { viewer } = context;
  const profile = await context.client
    .from("profiles")
    .select("*")
    .eq("user_id", context.userId)
    .single();
  const birthDate = storedBirthDate(profile.error ? null : profile.data);
  const profileTimezone = storedProfileTimezone(
    profile.error ? null : profile.data,
  );
  const semanticSearch = storedSemanticSearchPreference(
    profile.error ? null : profile.data,
  );
  const reviewSettings = await loadReviewSettings(context.client);
  const cookieStore = await cookies();
  const preferredName =
    !profile.error && typeof profile.data?.display_name === "string"
      ? profile.data.display_name.trim() || null
      : null;
  const accountName = preferredName ?? viewer.name;
  const themePreference = storedThemePreference(
    cookieStore.get(THEME_COOKIE_NAME)?.value,
  );

  const showProfile = !profile.error || birthDate.available;

  return (
    <PageFrame className={pageStyles.content} width="reading">
      <PageHeader title={<>Settings</>} />

      {showProfile ? (
        <section aria-labelledby="profile-heading">
          <SectionHeader
            headingId="profile-heading"
            title="Profile"
            variant="section"
          />
          {!profile.error ? (
            <PreferredNameSetting initialName={preferredName} />
          ) : null}
          {birthDate.available ? (
            <BirthDateSetting
              initialBirthDate={birthDate.birthDate}
              maxValue={new Date().toISOString().slice(0, 10)}
            />
          ) : null}
        </section>
      ) : null}

      {profileTimezone.available ? (
        <section aria-labelledby="time-heading">
          <SectionHeader
            headingId="time-heading"
            title="Time"
            variant="section"
          />
          <TimezoneSetting initialTimezone={profileTimezone.timezone} />
        </section>
      ) : null}

      <section aria-labelledby="appearance-heading">
        <SectionHeader
          headingId="appearance-heading"
          title="Appearance"
          variant="section"
        />
        <AppearanceSetting initialPreference={themePreference} />
      </section>

      {reviewSettings ? (
        <section aria-labelledby="reviews-heading" id="reviews">
          <SectionHeader
            headingId="reviews-heading"
            title="Reviews"
            variant="section"
          />
          <ReviewsSetting initial={reviewSettings} />
        </section>
      ) : null}

      {/* Without an embedding service search is keyword-only, so the switch would do nothing. */}
      {semanticSearch.available && semanticSearchConfigured() ? (
        <section aria-labelledby="search-heading">
          <SectionHeader
            headingId="search-heading"
            title="Search"
            variant="section"
          />
          <SemanticSearchSetting initialEnabled={semanticSearch.enabled} />
        </section>
      ) : null}

      <section aria-labelledby="data-heading">
        <SectionHeader
          headingId="data-heading"
          title="Your data"
          variant="section"
        />
        <DataRow
          action="Import"
          detail="Bring notes and journals from another app."
          href="/settings/import"
          label="Import"
        />
        <DataRow
          action="Export"
          detail="A complete, portable copy of everything you have written."
          href="/settings/export"
          label="Export"
        />
        <DataRow
          action="Open Tags"
          detail="Rename, merge, and clean up tags."
          href="/tags"
          label="Tags"
        />
      </section>

      <section aria-labelledby="account-heading">
        <SectionHeader
          headingId="account-heading"
          title="Account"
          variant="section"
        />
        <SettingRow id="account" label="Signed in">
          <div className={settingsFieldsStyles.account}>
            <div className={settingsFieldsStyles.who}>
              <span aria-hidden="true" className={settingsFieldsStyles.avatar}>
                {accountName.charAt(0).toUpperCase()}
              </span>
              <div className={settingsFieldsStyles.identity}>
                <strong>{accountName}</strong>
                <span>{viewer.email}</span>
                <span className={settingsFieldsStyles.provider}>
                  Google Sign-In
                </span>
              </div>
            </div>
            <form action={signOut}>
              <Button type="submit" variant="secondary">
                Sign out
              </Button>
            </form>
          </div>
        </SettingRow>
      </section>
    </PageFrame>
  );
}

/** A row that leads to another page: what it does, and a secondary button that goes there. */
function DataRow({
  action,
  detail,
  href,
  label,
}: {
  action: string;
  detail: string;
  href: string;
  label: string;
}) {
  return (
    <SettingRow id={`data-${label}`} label={label}>
      <div className={settingsFieldsStyles.linkControl}>
        <span>{detail}</span>
        <ButtonLink href={href} variant="secondary">
          {action}
        </ButtonLink>
      </div>
    </SettingRow>
  );
}
