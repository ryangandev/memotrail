import Link from "next/link";
import { cookies } from "next/headers";
import { signOut } from "@/app/auth/actions";
import { AppearanceSetting } from "@/components/appearance-setting";
import { Icon, type IconName } from "@/components/icon";
import { BirthDateSetting } from "@/components/birth-date-setting";
import { TimezoneSetting } from "@/components/timezone-setting";
import { PageFrame } from "@/components/page-frame";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  storedBirthDate,
  storedProfileTimezone,
} from "@/lib/data/profile-input";
import { storedThemePreference, THEME_COOKIE_NAME } from "@/lib/theme";
import styles from "./page.module.css";

export const dynamic = "force-dynamic";

const preferences: Array<{
  detail: string;
  href: string;
  icon: IconName;
  title: string;
}> = [
  {
    detail: "Choose when AI may help and review its privacy controls.",
    href: "/settings/ai",
    icon: "sparkle",
    title: "AI assistance",
  },
  {
    detail: "Open the Library to manage Collections and tags across Entries.",
    href: "/collections",
    icon: "archive",
    title: "Archive organization",
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
  const themePreference = storedThemePreference(
    (await cookies()).get(THEME_COOKIE_NAME)?.value,
  );

  return (
    <PageFrame className={styles.content} variant="compact">
      <header className={styles.header}>
        <p>Your private space</p>
        <h1>Settings</h1>
        <span>Manage your account and the way MemoTrail works for you.</span>
      </header>

      <section aria-labelledby="account-heading">
        <div className={styles.sectionHeading}>
          <div>
            <h2 id="account-heading">Account</h2>
            <p>Your current MemoTrail identity</p>
          </div>
          <span className={styles.connectedStatus}>Connected</span>
        </div>

        <div className={styles.accountCard}>
          <span className={styles.accountAvatar}>{viewer.initial}</span>
          <div className={styles.accountIdentity}>
            <strong>{viewer.name}</strong>
            <span>{viewer.email}</span>
            <small>Google Sign-In</small>
          </div>
          <form action={signOut}>
            <button type="submit">Sign out</button>
          </form>
        </div>

        {birthDate.available ? (
          <BirthDateSetting
            initialBirthDate={birthDate.birthDate}
            maxValue={new Date().toISOString().slice(0, 10)}
          />
        ) : null}
      </section>

      <section aria-labelledby="preferences-heading">
        <div className={styles.sectionHeading}>
          <div>
            <h2 id="preferences-heading">Preferences</h2>
            <p>Controls already available in this version</p>
          </div>
        </div>

        {profileTimezone.available ? (
          <TimezoneSetting initialTimezone={profileTimezone.timezone} />
        ) : null}

        <div className={styles.preferenceList}>
          <AppearanceSetting initialPreference={themePreference} />

          {preferences.map((preference) => (
            <Link href={preference.href} key={preference.href}>
              <span className={styles.preferenceIcon}>
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

      <aside className={styles.privacyNote}>
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
