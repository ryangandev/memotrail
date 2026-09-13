"use client";
import { useState } from "react";
import { saveAISettings } from "@/app/settings/ai/actions";
import {
  aiFeatures,
  featureLabels,
  formatAICost,
  type AIWorkspace,
} from "@/lib/ai/contracts";
import styles from "@/app/settings/ai/page.module.css";
export function AISettings({
  initial,
  configured,
}: {
  initial: AIWorkspace;
  configured: boolean;
}) {
  const [workspace, setWorkspace] = useState(initial);
  const [draft, setDraft] = useState(initial.preferences);
  const [budget, setBudget] = useState(
    String(draft.monthly_budget_micros / 1_000_000),
  );
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [testing, setTesting] = useState(false);
  async function save(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setMessage(null);
    try {
      if (!budget.trim() || !Number.isFinite(Number(budget))) {
        setMessage("Enter a monthly budget from $0 to $100.");
        return;
      }
      const result = await saveAISettings({
        ...draft,
        monthly_budget_micros: Math.round(Number(budget) * 1_000_000),
      });
      if (result.error) setMessage(result.error);
      else {
        setWorkspace(result.data);
        setDraft(result.data.preferences);
        setMessage("AI settings saved across your devices.");
      }
    } catch {
      setMessage("Could not save settings. Your edits are still here.");
    } finally {
      setBusy(false);
    }
  }
  async function test() {
    setTesting(true);
    setMessage(null);
    try {
      const response = await fetch("/api/ai/connection", { method: "POST" });
      const result = await response.json();
      setMessage(result.error ?? result.message);
      // Usage is refreshed on reload; do not replace an unsaved preference draft.
    } catch {
      setMessage("Could not reach the AI server. Try again later.");
    } finally {
      setTesting(false);
    }
  }
  return (
    <div className={styles.content}>
      <header>
        <p className={styles.eyebrow}>YOUR ARCHIVE, YOUR CHOICE</p>
        <h1>AI settings</h1>
        <p>
          Optional assistance. Your words and manual organization always remain
          yours.
        </p>
      </header>
      <section className={styles.card}>
        <h2>Provider & privacy</h2>
        <p>Anthropic · Claude Haiku 4.5</p>
        <p>
          {configured
            ? "Server connection is configured."
            : "This server still needs its AI configuration. Preferences can be saved now."}
        </p>
        <p>
          Enabled features send the relevant Entry text or search question to
          Anthropic. Photo analysis separately permits up to 12 compact,
          metadata-free previews for Inbox suggestions, never originals. Secrets
          stay on the server, never in the iOS app. Suggestions never silently
          overwrite your records or mark them Done.
        </p>
        <p>
          Feature switches grant permission; they do not start a bulk analysis
          of your archive.
        </p>
      </section>
      <form className={styles.card} onSubmit={save}>
        <label className={styles.toggle}>
          <span>
            <strong>Enable AI assistance</strong>
            <small>
              Off by default. Turn off to stop new AI requests on every device.
            </small>
          </span>
          <input
            type="checkbox"
            checked={draft.enabled}
            onChange={(e) => setDraft({ ...draft, enabled: e.target.checked })}
            disabled={busy || testing}
          />
        </label>
        <fieldset disabled={busy || testing || !draft.enabled}>
          <legend>Allow these features</legend>
          {aiFeatures.map((feature) => (
            <label className={styles.toggle} key={feature}>
              <span>{featureLabels[feature]}</span>
              <input
                type="checkbox"
                checked={draft[feature]}
                onChange={(e) =>
                  setDraft({ ...draft, [feature]: e.target.checked })
                }
              />
            </label>
          ))}
        </fieldset>
        <label className={styles.budget}>
          Monthly budget (USD)
          <input
            type="number"
            step="0.01"
            min="0"
            max="100"
            required
            value={budget}
            disabled={busy || testing}
            onChange={(e) => setBudget(e.target.value)}
          />
        </label>
        <p>
          Resets at the start of each UTC month. A separate server-wide total
          cap can stop requests earlier. This is a MemoTrail spending guard, not
          your Anthropic account balance.
        </p>
        <div className={styles.actions}>
          <button disabled={busy || testing} type="submit">
            {busy ? "Saving…" : "Save AI settings"}
          </button>
          <button
            type="button"
            disabled={
              busy || testing || !configured || !workspace.preferences.enabled
            }
            onClick={test}
          >
            {testing ? "Testing…" : "Test connection"}
          </button>
        </div>
        <p>
          A connection test sends only synthetic text and has a small usage
          cost. Save Enable AI first.
        </p>
        {message && (
          <p role="status" className={styles.message}>
            {message}
          </p>
        )}
      </form>
      <section className={styles.card}>
        <h2>Usage this month</h2>
        <p className={styles.amount}>
          {formatAICost(workspace.month_charged_micros)}{" "}
          <span>
            of {formatAICost(workspace.preferences.monthly_budget_micros)}
          </span>
        </p>
        <p>
          Includes in-flight and uncertain reservations. Completed requests use
          reported token counts at $1 / million input and $5 / million output
          tokens. Reload to refresh usage after a test.
        </p>
        {workspace.recent_usage.length === 0 ? (
          <p>No AI requests yet.</p>
        ) : (
          <ul className={styles.usage}>
            {workspace.recent_usage.map((item) => (
              <li key={item.id}>
                <div>
                  <strong>{item.feature.replaceAll("_", " ")}</strong>
                  <small>
                    {new Date(item.created_at).toLocaleString()} · {item.status}
                  </small>
                </div>
                <span>{formatAICost(item.charged_micros)}</span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
