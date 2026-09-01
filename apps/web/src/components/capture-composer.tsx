"use client";

import { useActionState, useEffect, useRef } from "react";
import { createInboxEntry, type CaptureEntryState } from "@/app/inbox/actions";
import { Icon } from "@/components/icon";
import { entryBodyLimit, entryTitleLimit } from "@/lib/data/inbox-input";
import styles from "@/app/page.module.css";

const initialCaptureEntryState: CaptureEntryState = {
  message: "",
  submissionId: null,
  type: "idle",
};

export function CaptureComposer() {
  const [state, formAction, isPending] = useActionState(
    createInboxEntry,
    initialCaptureEntryState,
  );
  const formRef = useRef<HTMLFormElement>(null);

  useEffect(() => {
    if (state.type === "success") {
      formRef.current?.reset();
    }
  }, [state.submissionId, state.type]);

  return (
    <form
      action={formAction}
      className={styles.captureCard}
      ref={formRef}
      aria-labelledby="capture-heading"
    >
      <div className={styles.captureIntro}>
        <span className={styles.captureSpark} aria-hidden="true">
          <Icon name="sparkle" size={19} />
        </span>
        <div className={styles.captureFields}>
          <label className={styles.visuallyHidden} htmlFor="capture-title">
            Entry title
          </label>
          <input
            autoComplete="off"
            className={styles.captureTitle}
            disabled={isPending}
            id="capture-title"
            maxLength={entryTitleLimit}
            name="title"
            placeholder="What is worth keeping?"
          />
          <label className={styles.visuallyHidden} htmlFor="capture-body">
            Entry text
          </label>
          <textarea
            className={styles.captureBody}
            disabled={isPending}
            id="capture-body"
            maxLength={entryBodyLimit}
            name="body"
            placeholder="A thought, a first, something learned, or whatever is on your mind."
            rows={4}
          />
        </div>
      </div>
      <div className={styles.captureActions}>
        <div>
          <button
            aria-label="Voice capture is coming next"
            className={styles.quietButton}
            disabled
            type="button"
          >
            <Icon name="mic" /> Voice
          </button>
          <button
            aria-label="Photo capture is coming next"
            className={styles.quietButton}
            disabled
            type="button"
          >
            <Icon name="photo" /> Photo
          </button>
        </div>
        <div className={styles.captureSubmitGroup}>
          <p
            className={
              state.type === "error"
                ? styles.captureError
                : styles.captureStatus
            }
            aria-live="polite"
          >
            {state.message}
          </p>
          <button
            className={styles.saveButton}
            disabled={isPending}
            type="submit"
          >
            {isPending ? "Saving…" : "Save to Inbox"}
            <Icon name="chevron" size={16} />
          </button>
        </div>
      </div>
    </form>
  );
}
