"use client";

import { useRouter } from "next/navigation";
import { useId, useState } from "react";
import { saveReviewPreferences } from "@/app/reviews/actions";
import { notify } from "@/components/app-toast";
import { Button } from "@/components/button";
import { useConfirmationDialog } from "@/components/confirmation-dialog";
import { ReviewDisclosureDialog } from "@/components/review-disclosure-dialog";
import { SettingRow, settingRowIds } from "@/components/setting-row";
import { SettingSwitch } from "@/components/setting-switch";
import styles from "@/components/settings-fields.module.css";
import { REVIEW_DISCLOSURE_VERSION } from "@/lib/ai/review-disclosure";
import type { ReviewSettings } from "@/lib/data/review-input";

type Switch = "reviews" | "suggestions";

/**
 * The two review switches and the disclosure behind them. A switch turns on only after the
 * person has seen what is sent, and turning reviews off deletes the saved ones after asking.
 */
export function ReviewsSetting({ initial }: { initial: ReviewSettings }) {
  const router = useRouter();
  const requestConfirmation = useConfirmationDialog();
  const [settings, setSettings] = useState(initial);
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState<Switch | null>(null);
  const reviewsId = useId();
  const suggestionsId = useId();
  const [dialog, setDialog] = useState<
    { mode: "read" } | { mode: "accept"; turnOn: Switch } | null
  >(null);

  const accepted = settings.disclosureVersion === REVIEW_DISCLOSURE_VERSION;

  async function save(
    next: { reviews: boolean; suggestions: boolean },
    acceptDisclosure: boolean,
    which: Switch,
  ) {
    if (busy) return false;
    setBusy(true);
    setSaved(null);
    try {
      const result = await saveReviewPreferences({
        ...next,
        acceptDisclosure,
        revision: settings.revision,
      });
      if (result.status === "saved") {
        setSettings(result.settings);
        setSaved(which);
        notify.success(
          next.reviews !== settings.reviewsEnabled
            ? result.message
            : next.suggestions
              ? "Chapter suggestions are on."
              : "Chapter suggestions are off.",
        );
        router.refresh();
        return true;
      }
      notify.error(result.message);
      if (result.status === "stale") router.refresh();
    } catch {
      notify.error(
        "MemoTrail could not save this setting. Check your connection and try again.",
      );
    } finally {
      setBusy(false);
    }
    return false;
  }

  async function change(which: Switch, next: boolean) {
    if (busy) return;
    if (next && !accepted) {
      setDialog({ mode: "accept", turnOn: which });
      return;
    }
    if (which === "reviews" && !next && settings.reviewCount > 0) {
      const count = settings.reviewCount;
      const confirmed = await requestConfirmation({
        title: <>Turn off reviews?</>,
        description: (
          <>
            Your {count} saved {count === 1 ? "review" : "reviews"} will be
            deleted. Your Entries are not changed.
          </>
        ),
        confirmLabel: "Turn off and delete",
        eyebrow: <>Deletes saved reviews</>,
        variant: "danger",
      });
      if (!confirmed) return;
    }
    await save(
      {
        reviews: which === "reviews" ? next : settings.reviewsEnabled,
        suggestions:
          which === "suggestions" ? next : settings.chapterSuggestionsEnabled,
      },
      false,
      which,
    );
  }

  async function accept(turnOn: Switch) {
    const done = await save(
      {
        reviews: turnOn === "reviews" ? true : settings.reviewsEnabled,
        suggestions:
          turnOn === "suggestions" ? true : settings.chapterSuggestionsEnabled,
      },
      true,
      turnOn,
    );
    if (done) setDialog(null);
  }

  const reviewsIds = settingRowIds(reviewsId);
  const suggestionsIds = settingRowIds(suggestionsId);

  return (
    <>
      <SettingRow
        help="Turning this off deletes your saved reviews."
        id={reviewsId}
        label="Chapter and year reviews"
        saved={saved === "reviews"}
      >
        <div className={styles.switchControl}>
          <span>
            When you ask, Claude writes a review of a Chapter or a year from
            your Entries.
          </span>
          <SettingSwitch
            aria-describedby={reviewsIds.help}
            aria-labelledby={reviewsIds.label}
            checked={settings.reviewsEnabled}
            disabled={busy}
            onChange={(event) => void change("reviews", event.target.checked)}
          />
        </div>
      </SettingRow>
      <SettingRow
        help="Nothing becomes a Chapter until you add it."
        id={suggestionsId}
        label="Suggest Chapters"
        saved={saved === "suggestions"}
      >
        <div className={styles.switchControl}>
          <span>
            About once a month, Claude may suggest a Chapter from what you have
            been writing.
          </span>
          <SettingSwitch
            aria-describedby={suggestionsIds.help}
            aria-labelledby={suggestionsIds.label}
            checked={settings.chapterSuggestionsEnabled}
            disabled={busy}
            onChange={(event) =>
              void change("suggestions", event.target.checked)
            }
          />
        </div>
      </SettingRow>
      <div className={styles.sectionNote}>
        <Button
          onClick={() => setDialog({ mode: "read" })}
          size="small"
          variant="quiet"
        >
          What is sent and to whom
        </Button>
      </div>
      <ReviewDisclosureDialog
        busy={busy}
        confirmLabel={dialog?.mode === "accept" ? "Turn on" : undefined}
        onClose={() => setDialog(null)}
        onConfirm={
          dialog?.mode === "accept"
            ? () => void accept(dialog.turnOn)
            : undefined
        }
        open={dialog !== null}
      />
    </>
  );
}
