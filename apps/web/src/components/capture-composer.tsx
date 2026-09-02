"use client";

import { useActionState, useCallback, useEffect, useState } from "react";
import { createInboxEntry, type CaptureEntryState } from "@/app/inbox/actions";
import { Icon } from "@/components/icon";
import {
  clearInboxDraft,
  loadInboxDraft,
  persistInboxDraft,
} from "@/lib/data/inbox-draft";
import { entryBodyLimit, entryTitleLimit } from "@/lib/data/inbox-input";
import styles from "@/app/page.module.css";

const initialCaptureEntryState: CaptureEntryState = {
  message: "",
  submissionId: null,
  type: "idle",
};

export function CaptureComposer({ ownerId }: { ownerId: string }) {
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [isDraftReady, setIsDraftReady] = useState(false);
  const [hasLocalDraft, setHasLocalDraft] = useState(false);
  const saveEntry = useCallback(
    async (previousState: CaptureEntryState, formData: FormData) => {
      const nextState = await createInboxEntry(previousState, formData);

      if (nextState.type === "success") {
        clearInboxDraft(window.localStorage, ownerId);
        setTitle("");
        setBody("");
        setHasLocalDraft(false);
      }

      return nextState;
    },
    [ownerId],
  );
  const [state, formAction, isPending] = useActionState(
    saveEntry,
    initialCaptureEntryState,
  );

  useEffect(() => {
    const draft = loadInboxDraft(window.localStorage, ownerId);
    let isCanceled = false;

    queueMicrotask(() => {
      if (isCanceled) {
        return;
      }

      setTitle(draft?.title ?? "");
      setBody(draft?.body ?? "");
      setHasLocalDraft(Boolean(draft));
      setIsDraftReady(true);
    });

    return () => {
      isCanceled = true;
    };
  }, [ownerId]);

  function updateDraft(nextTitle: string, nextBody: string) {
    setTitle(nextTitle);
    setBody(nextBody);
    setHasLocalDraft(
      persistInboxDraft(window.localStorage, ownerId, {
        body: nextBody,
        title: nextTitle,
      }),
    );
  }

  const feedback = captureFeedback(state, hasLocalDraft);

  return (
    <form
      action={formAction}
      className={styles.captureCard}
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
            disabled={isPending || !isDraftReady}
            id="capture-title"
            maxLength={entryTitleLimit}
            name="title"
            onChange={(event) => updateDraft(event.target.value, body)}
            placeholder="What is worth keeping?"
            value={title}
          />
          <label className={styles.visuallyHidden} htmlFor="capture-body">
            Entry text
          </label>
          <textarea
            className={styles.captureBody}
            disabled={isPending || !isDraftReady}
            id="capture-body"
            maxLength={entryBodyLimit}
            name="body"
            onChange={(event) => updateDraft(title, event.target.value)}
            placeholder="A thought, a first, something learned, or whatever is on your mind."
            rows={4}
            value={body}
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
              feedback.isError ? styles.captureError : styles.captureStatus
            }
            aria-live="polite"
          >
            {feedback.message}
          </p>
          <button
            className={styles.saveButton}
            disabled={isPending || !isDraftReady}
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

function captureFeedback(state: CaptureEntryState, hasLocalDraft: boolean) {
  if (state.type === "error") {
    return { isError: true, message: state.message };
  }

  if (hasLocalDraft) {
    return { isError: false, message: "Draft saved on this device." };
  }

  return { isError: false, message: state.message };
}
