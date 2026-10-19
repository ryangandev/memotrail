import pageStyles from "@/app/settings/page.module.css";
import settingsFieldsStyles from "@/components/settings-fields.module.css";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/button";
import Link from "next/link";
import { cookies } from "next/headers";
import { signOut } from "@/app/auth/actions";
import { AppearanceSetting } from "@/components/appearance-setting";
import { Icon, type IconName } from "@/components/icon";
import { BirthDateSetting } from "@/components/birth-date-setting";
import { TimezoneSetting } from "@/components/timezone-setting";
import { PageFrame } from "@/components/page-frame";
import { SectionHeader } from "@/components/section-header";
import { PreferredNameSetting } from "@/components/preferred-name-setting";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  storedBirthDate,
  storedProfileTimezone,
} from "@/lib/data/profile-input";
import { storedThemePreference, THEME_COOKIE_NAME } from "@/lib/theme";

export const dynamic = "force-dynamic";

const preferences: Array<{
  detail: string;
  href: string;
  icon: IconName;
  title: string;
}> = [
  {
    detail: "Off and unavailable while we rethink how AI can help.",
    href: "/settings/ai",
    icon: "sparkle",
    title: "AI capabilities · Beta",
  },
  {
    detail: "Rename, merge, and clean up the tags across your archive.",
    href: "/tags",
    icon: "tag",
    title: "Archive organization",
  },
  {
    detail: "Bring notes and journals from another app into your archive.",
    href: "/settings/import",
    icon: "plus",
    title: "Import notes",
  },
  {
    detail: "Create a complete portable copy of your private archive.",
    href: "/settings/export",
    icon: "archive",
    title: "Export archive",
  },
];

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
  const cookieStore = await cookies();
  const preferredName =
    !profile.error && typeof profile.data?.display_name === "string"
      ? profile.data.display_name.trim() || null
      : null;
  const accountName = preferredName ?? viewer.name;
  const themePreference = storedThemePreference(
    cookieStore.get(THEME_COOKIE_NAME)?.value,
  );

  return (
    <PageFrame className={pageStyles.content} variant="compact">
      <PageHeader
        title={<>Settings</>}
        eyebrow={<>Your private space</>}
        description={
          <>Manage your account and the way MemoTrail works for you.</>
        }
      />

      <section aria-labelledby="account-heading">
        <SectionHeader
          action={<span className={pageStyles.connectedStatus}>Connected</span>}
          className={pageStyles.sectionHeading}
          description="Your current MemoTrail identity"
          headingId="account-heading"
          title="Account"
          variant="list"
        />

        <div className={pageStyles.accountCard}>
          <span className={pageStyles.accountAvatar}>
            {accountName.charAt(0).toUpperCase()}
          </span>
          <div className={pageStyles.accountIdentity}>
            <strong>{accountName}</strong>
            <span>{viewer.email}</span>
            <small>Google Sign-In</small>
          </div>
          <form action={signOut}>
            <Button variant="primary" type="submit">
              Sign out
            </Button>
          </form>
        </div>

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

      <section aria-labelledby="preferences-heading">
        <SectionHeader
          className={pageStyles.sectionHeading}
          description="Controls already available in this version"
          headingId="preferences-heading"
          title="Preferences"
          variant="list"
        />

        {profileTimezone.available ? (
          <TimezoneSetting initialTimezone={profileTimezone.timezone} />
        ) : null}

        <div className={pageStyles.preferenceList}>
          <AppearanceSetting initialPreference={themePreference} />

          {preferences.map((preference) => (
            <Link href={preference.href} key={preference.href}>
              <span className={settingsFieldsStyles.preferenceIcon}>
                <Icon name={preference.icon} size={20} />
              </span>
              <div>
                <strong>{preference.title}</strong>
                <p>{preference.detail}</p>
              </div>
              <Icon name="chevron" size={16} />
            </Link>
          ))}
        </div>
      </section>

      <aside className={pageStyles.privacyNote}>
        <Icon name="check" size={18} />
        <div>
          <strong>Private by default</strong>
          <p>
            Your account and archive are not shared with other MemoTrail users.
          </p>
        </div>
      </aside>
    </PageFrame>
  );
}
