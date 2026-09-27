"use client";
import { notify } from "@/components/app-toast";
import { PageHeader } from "@/components/page-header";

import { useState } from "react";
import { saveAISettings } from "@/app/settings/ai/actions";
import styles from "@/components/ai-settings.module.css";
import { Icon, type IconName } from "@/components/icon";
import { PageFrame } from "@/components/page-frame";
import { Badge } from "@/components/badge";
import {
  simpleAIControlChecked,
  updateSimpleAIPreferences,
  type AIUsage,
  type AIWorkspace,
  type SimpleAIControl,
} from "@/lib/ai/contracts";

const activityLabels: Record<string, string> = {
  classification: "Organizing suggestions",
  explore: "Explore with AI",
  photo_analysis: "Photo understanding",
  search: "AI search",
  tagging: "Organizing suggestions",
};

const activityStatuses: Record<AIUsage["status"], string> = {
  completed: "Completed",
  failed: "Not completed",
  reserved: "In progress",
  uncertain: "Interrupted",
};

type AISettingsProps = {
  configured: boolean;
  initial: AIWorkspace;
  monthRequestCount: number | null;
};

export function AISettings({
  configured,
  initial,
  monthRequestCount,
}: AISettingsProps) {
  const [workspace, setWorkspace] = useState(initial);
  const [busyControl, setBusyControl] = useState<SimpleAIControl | null>(null);
  const preferences = workspace.preferences;
  const monthlyLimitReached =
    preferences.monthly_budget_micros === 0 ||
    workspace.month_charged_micros >= preferences.monthly_budget_micros;
  const recentActivity = workspace.recent_usage
    .filter((item) => item.feature !== "connection")
    .slice(0, 5);

  async function update(control: SimpleAIControl, checked: boolean) {
    if (busyControl) return;
    const previous = workspace;
    const nextPreferences = updateSimpleAIPreferences(
      preferences,
      control,
      checked,
    );
    setWorkspace({ ...workspace, preferences: nextPreferences });
    setBusyControl(control);

    try {
      const result = await saveAISettings(nextPreferences);
      if (result.error || !result.data) {
        setWorkspace(previous);
        notify.error(result.error ?? "Could not save AI preferences.");
        return;
      }
      setWorkspace(result.data as AIWorkspace);
      notify.success(savedMessage(control, checked));
    } catch {
      setWorkspace(previous);
      notify.error("Could not save AI preferences. Try again.");
    } finally {
      setBusyControl(null);
    }
  }

  const availability = !configured
    ? "Unavailable"
    : monthlyLimitReached
      ? "Monthly limit reached"
      : "Available";

  return (
    <PageFrame className={styles.content} variant="compact">
      <PageHeader
        title={<>AI assistance</>}
        eyebrow={<>Your archive, your choice</>}
        description={
          <>
            Choose when MemoTrail may help. Your original words always remain
            yours.
          </>
        }
      />

      <section className={styles.primaryCard} aria-labelledby="ai-master-title">
        <div className={styles.primaryHeading}>
          <span className={styles.primaryIcon}>
            <Icon name="sparkle" size={22} />
          </span>
          <div>
            <h2 id="ai-master-title">Use AI in MemoTrail</h2>
            <p>
              Get help organizing memories, searching your archive, and
              exploring an Entry.
            </p>
          </div>
          <Badge
            className={styles.availability}
            tone={configured && !monthlyLimitReached ? "accent" : "neutral"}
            uppercase
          >
            {availability}
          </Badge>
        </div>

        <PreferenceSwitch
          checked={simpleAIControlChecked(preferences, "enabled")}
          description="Off by default. Turning this off stops new AI requests on every device."
          disabled={busyControl !== null}
          label="AI assistance"
          onChange={(checked) => void update("enabled", checked)}
          pending={busyControl === "enabled"}
        />

        {!configured ? (
          <p className={styles.unavailableNote}>
            AI is not available on this server yet. You can choose your
            preferences now, and no content will be sent until the service is
            available.
          </p>
        ) : null}

        <p className={styles.saveStatus} role="status">
          {busyControl ? "Saving..." : "Changes save automatically."}
        </p>
      </section>

      <section aria-labelledby="ai-features-title">
        <div className={styles.sectionHeading}>
          <div>
            <h2 id="ai-features-title">How AI helps</h2>
            <p>Simple controls based on what you are trying to do</p>
          </div>
        </div>

        <div className={styles.preferenceList}>
          <FeaturePreference
            checked={simpleAIControlChecked(preferences, "organizing")}
            description="Offers optional title, type, Collection, date, and tag suggestions while you review an Entry."
            disabled={busyControl !== null || !preferences.enabled}
            icon="tag"
            label="Suggestions while organizing"
            onChange={(checked) => void update("organizing", checked)}
            pending={busyControl === "organizing"}
          />

          <div className={styles.featureRow}>
            <span className={styles.featureIcon}>
              <Icon name="search" size={20} />
            </span>
            <div>
              <strong>Search and explore</strong>
              <p>
                Runs only when you choose Ask AI or Explore with AI. Normal
                keyword search never requires AI.
              </p>
            </div>
            <Badge className={styles.onDemandBadge} tone="neutral" uppercase>
              When you ask
            </Badge>
          </div>

          <FeaturePreference
            checked={simpleAIControlChecked(preferences, "photo_analysis")}
            description="Lets organizing suggestions consider compact photo previews. Originals and photo metadata are not shared."
            disabled={busyControl !== null || !preferences.enabled}
            icon="photo"
            label="Understand photos"
            onChange={(checked) => void update("photo_analysis", checked)}
            pending={busyControl === "photo_analysis"}
          />
        </div>
      </section>

      <aside className={styles.privacyNote}>
        <Icon name="check" size={18} />
        <div>
          <strong>You stay in control</strong>
          <p>
            AI suggestions never replace your writing, reorganize an Entry, or
            mark anything complete without your action.
          </p>
          <details>
            <summary>What is shared with AI?</summary>
            <p>
              MemoTrail sends only the relevant Entry text or search question to
              its configured AI provider. If Understand photos is on, it may
              also send up to 12 compact, metadata-free previews, never original
              image files. Provider credentials remain on the server.
            </p>
          </details>
        </div>
      </aside>

      <section aria-labelledby="ai-usage-title">
        <div className={styles.sectionHeading}>
          <div>
            <h2 id="ai-usage-title">Usage this month</h2>
            <p>AI activity is limited automatically</p>
          </div>
        </div>

        <div className={styles.usageCard}>
          <div className={styles.usageSummary}>
            <p>
              <strong>{monthRequestCount ?? "-"}</strong>
              <span>
                {monthRequestCount === 1 ? "AI action" : "AI actions"} this
                month
              </span>
            </p>
            <Badge tone={monthlyLimitReached ? "warm" : "neutral"} uppercase>
              {monthlyLimitReached
                ? "Monthly limit reached"
                : "Within monthly limit"}
            </Badge>
          </div>

          {recentActivity.length ? (
            <details className={styles.activityDetails}>
              <summary>View recent activity</summary>
              <ul>
                {recentActivity.map((item) => (
                  <li key={item.id}>
                    <span>
                      {activityLabels[item.feature] ?? "AI assistance"}
                    </span>
                    <small>{activityStatuses[item.status]}</small>
                  </li>
                ))}
              </ul>
            </details>
          ) : (
            <p className={styles.emptyUsage}>No AI activity yet.</p>
          )}
        </div>
      </section>
    </PageFrame>
  );
}

type PreferenceSwitchProps = {
  checked: boolean;
  description: string;
  disabled: boolean;
  label: string;
  onChange: (checked: boolean) => void;
  pending: boolean;
};

function PreferenceSwitch({
  checked,
  description,
  disabled,
  label,
  onChange,
  pending,
}: PreferenceSwitchProps) {
  return (
    <label className={styles.switchRow}>
      <span>
        <strong>{label}</strong>
        <small>{description}</small>
      </span>
      <span className={styles.switchControl}>
        <input
          aria-label={label}
          checked={checked}
          disabled={disabled}
          onChange={(event) => onChange(event.target.checked)}
          role="switch"
          type="checkbox"
        />
        <span aria-hidden="true" className={styles.switchTrack}>
          <span />
        </span>
        {pending ? <span className={styles.pendingText}>Saving</span> : null}
      </span>
    </label>
  );
}

function FeaturePreference({
  icon,
  ...switchProps
}: PreferenceSwitchProps & { icon: IconName }) {
  return (
    <div className={styles.featureRow}>
      <span className={styles.featureIcon}>
        <Icon name={icon} size={20} />
      </span>
      <PreferenceSwitch {...switchProps} />
    </div>
  );
}

function savedMessage(control: SimpleAIControl, checked: boolean) {
  if (control === "enabled") {
    return `AI assistance is ${checked ? "on" : "off"}.`;
  }
  if (control === "organizing") {
    return `Organizing suggestions are ${checked ? "on" : "off"}.`;
  }
  return `Photo understanding is ${checked ? "on" : "off"}.`;
}
