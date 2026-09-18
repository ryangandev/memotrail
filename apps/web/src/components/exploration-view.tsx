"use client";
import { Button } from "@/components/button";
import { useConfirmationDialog } from "@/components/confirmation-dialog";
import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import type {
  ExplorationRequest,
  ExplorationTurn,
  ExplorationWorkspace,
} from "@/lib/ai/exploration";
import styles from "@/components/exploration-view.module.css";
class ExplorationFailure extends Error {
  constructor(
    message: string,
    readonly code?: string,
  ) {
    super(message);
  }
}
async function api<T>(body: ExplorationRequest): Promise<T> {
  const response = await fetch("/api/ai/explore", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(60_000),
  });
  const result = await response.json();
  if (!response.ok)
    throw new ExplorationFailure(
      result.error || "Exploration is unavailable.",
      result.code,
    );
  return result;
}
export function ExplorationView({
  initial,
}: {
  initial: ExplorationWorkspace;
}) {
  const requestConfirmation = useConfirmationDialog();
  const [workspace, setWorkspace] = useState(initial);
  const [question, setQuestion] = useState("");
  const [busy, setBusy] = useState(false);
  const active = useRef(false);
  const [pending, setPending] = useState<Extract<
    ExplorationRequest,
    { action: "send" }
  > | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [save, setSave] = useState<{
    turnID: string;
    title: string;
    body: string;
    requestID: string;
    attempted: boolean;
  } | null>(null);
  const [savedID, setSavedID] = useState<string | null>(null);
  const saveEditor = useRef<HTMLElement>(null);
  const saveRequestID = save?.requestID;
  useEffect(() => {
    if (saveRequestID)
      saveEditor.current?.scrollIntoView({
        block: "start",
        behavior: "smooth",
      });
  }, [saveRequestID]);
  const pollCount = useRef(0);
  const entryID = initial.source.id;
  const generating = workspace.turns.some((t) => t.status === "generating");
  async function reload(older = false) {
    const data = await api<ExplorationWorkspace>({
      action: "workspace",
      entryID,
      ...(older && workspace.turns[0]
        ? { beforeSequence: workspace.turns[0].sequence }
        : {}),
    });
    setWorkspace((current) => ({
      ...data,
      turns: older
        ? [
            ...data.turns,
            ...current.turns.filter(
              (t) => !data.turns.some((v) => v.id === t.id),
            ),
          ]
        : data.turns,
    }));
    setPending((current) =>
      current &&
      data.turns.some(
        (t) => t.id === current.requestID && t.status !== "generating",
      )
        ? null
        : current,
    );
  }
  // Polling only reads persisted state, never retries model generation.
  useEffect(() => {
    if (!generating || busy || pollCount.current >= 12) return;
    const timer = setTimeout(() => {
      pollCount.current += 1;
      void api<ExplorationWorkspace>({ action: "workspace", entryID })
        .then((data) => {
          setWorkspace(data);
          setPending((current) =>
            current &&
            data.turns.some(
              (t) => t.id === current.requestID && t.status !== "generating",
            )
              ? null
              : current,
          );
        })
        .catch(() =>
          setError(
            "Could not refresh. Use Refresh conversation to check the saved state.",
          ),
        );
    }, 5000);
    return () => clearTimeout(timer);
  }, [generating, busy, workspace, entryID]);
  async function run(task: () => Promise<void>) {
    if (active.current) return;
    active.current = true;
    setBusy(true);
    setError(null);
    try {
      await task();
    } catch (e) {
      setError(
        e instanceof Error
          ? e.message
          : "The request was interrupted. Refresh before trying again.",
      );
    } finally {
      active.current = false;
      setBusy(false);
    }
  }
  async function send() {
    await run(async () => {
      const input = pending ?? {
        action: "send" as const,
        entryID,
        requestID: crypto.randomUUID(),
        question: question.trim(),
        sourceRevision: workspace.source.revision,
      };
      setPending(input);
      let data: ExplorationWorkspace;
      try {
        data = await api<ExplorationWorkspace>(input);
      } catch (error) {
        // These failures happen before claiming a generation. Unknown failures retain identity.
        if (
          error instanceof ExplorationFailure &&
          [
            "entry_changed",
            "entry_unavailable",
            "exploration_busy",
            "request_id_conflict",
            "ai_disabled",
            "provider_unavailable",
            "invalid_request",
          ].includes(error.code ?? "")
        )
          setPending(null);
        throw error;
      }
      setWorkspace(data);
      setPending(null);
      pollCount.current = 0;
      if (
        data.turns.some(
          (t) => t.id === input.requestID && t.status === "completed",
        )
      )
        setQuestion("");
    });
  }
  async function selectConclusion(turn: ExplorationTurn) {
    if (save) {
      const confirmed = await requestConfirmation({
        title: <>Replace the open conclusion draft?</>,
        description: (
          <>
            If its save was interrupted, refresh first to check whether it was
            saved.
          </>
        ),
        confirmLabel: "Replace draft",
        eyebrow: <>Unsaved work</>,
        variant: "danger",
      });
      if (!confirmed) return;
    }
    setSave({
      turnID: turn.id,
      title: "",
      body: turn.answer ?? "",
      requestID: crypto.randomUUID(),
      attempted: false,
    });
    setSavedID(null);
    setError(null);
  }
  return (
    <>
      <section className={styles.source} aria-label="Original Entry">
        <p className={styles.eyebrow}>
          ORIGINAL ENTRY · VERSION {workspace.source.revision}
        </p>
        <h2>{workspace.source.title || "Untitled Entry"}</h2>
        <p className={styles.writing}>{workspace.source.body}</p>
        <Link href={`/items/${entryID}`}>Open original Entry</Link>
      </section>
      {workspace.links.length > 0 && (
        <nav className={styles.links} aria-label="Exploration links">
          {workspace.links.map((link) => (
            <Link
              key={`${link.id}:${link.relationship}`}
              href={`/items/${link.id}`}
            >
              {link.relationship === "exploration_source"
                ? "Source"
                : "Saved conclusion"}
              : {link.title}
            </Link>
          ))}
          {workspace.linksTruncated && <p>Showing the first 100 links.</p>}
        </nav>
      )}
      <div className={styles.toolbar}>
        <Button
          variant="secondary"
          type="submit"
          disabled={busy}
          onClick={() => {
            pollCount.current = 0;
            void run(() => reload());
          }}
        >
          Refresh conversation
        </Button>
        <Link href="/settings/ai">AI settings</Link>
      </div>
      <p className={styles.notice}>
        Sending shares a bounded excerpt of this Entry and up to eight recent
        completed turns with Anthropic. No photos or other archive records are
        sent. AI may be wrong; distinguish its interpretations from your
        memories. Opening this page and refreshing are free.
      </p>
      {workspace.turns.length < workspace.total_count && (
        <Button
          variant="secondary"
          type="submit"
          disabled={busy}
          onClick={() => void run(() => reload(true))}
        >
          Load earlier turns
        </Button>
      )}
      <section
        className={styles.conversation}
        aria-label="Exploration conversation"
      >
        {!workspace.turns.length && (
          <p className={styles.empty}>
            Start with a question, a new perspective, or something you want to
            understand.
          </p>
        )}
        {workspace.turns.map((turn) => (
          <article key={turn.id} className={styles.turn}>
            <p className={styles.eyebrow}>YOU</p>
            <p className={styles.writing}>{turn.question}</p>
            <p className={styles.eyebrow}>
              AI EXPLORATION · SOURCE VERSION {turn.source_revision}
            </p>
            {turn.status === "completed" ? (
              <>
                <p className={styles.writing}>{turn.answer}</p>
                <Button
                  variant="primary"
                  type="submit"
                  disabled={busy}
                  onClick={() => void selectConclusion(turn)}
                >
                  Save as Entry
                </Button>
              </>
            ) : (
              <p role="status">
                {turn.status === "generating"
                  ? "Processing. You can leave and return; do not send the same question again."
                  : "This attempt did not finish. No automatic retry was made."}
              </p>
            )}
            {turn.status === "failed" && (
              <Button
                variant="secondary"
                type="submit"
                disabled={busy}
                onClick={() => {
                  setPending(null);
                  setQuestion(turn.question);
                  setError(null);
                }}
              >
                Use question for a new attempt
              </Button>
            )}
            <details>
              <summary>Recorded source snapshot</summary>
              <p className={styles.notice}>
                The model uses a bounded excerpt of this snapshot. Its version
                is retained even if you later edit the Entry.
              </p>
              <p className={styles.writing}>
                {String(turn.source_snapshot.body ?? "")}
              </p>
            </details>
            {turn.saved_entries?.map((entry) =>
              entry.entry_id && !entry.deleted ? (
                <Link
                  className={styles.saved}
                  key={entry.request_id}
                  href={`/items/${entry.entry_id}`}
                >
                  Saved Entry: {entry.title || "Untitled Entry"}
                </Link>
              ) : (
                <p className={styles.notice} key={entry.request_id}>
                  A saved conclusion was removed. Old retries will not recreate
                  it.
                </p>
              ),
            )}
          </article>
        ))}
      </section>
      <form
        className={styles.composer}
        onSubmit={(e) => {
          e.preventDefault();
          void send();
        }}
      >
        <label htmlFor="explore-question">Your question</label>
        <textarea
          id="explore-question"
          value={question}
          maxLength={2000}
          rows={4}
          disabled={busy || Boolean(pending)}
          onChange={(e) => setQuestion(e.target.value)}
          placeholder="What could I learn from this thought?"
        />
        <Button
          variant="primary"
          type="submit"
          disabled={busy || generating || !question.trim()}
        >
          {busy
            ? "Working…"
            : pending
              ? "Retry the same request"
              : "Send question"}
        </Button>
        {pending && (
          <p className={styles.notice}>
            The last request is unconfirmed. Refresh to check the conversation.
            Retrying uses the same request ID to prevent duplicate generation.
          </p>
        )}
      </form>
      {save && (
        <section
          ref={saveEditor}
          className={styles.save}
          aria-label="Save conclusion as Entry"
        >
          <h2>Keep a conclusion</h2>
          <p>
            Edit the wording before saving. This creates a separate Inbox Entry
            linked both ways to the original.
          </p>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              void run(async () => {
                setSave({ ...save, attempted: true });
                const result = await api<{ entry_id: string | null }>({
                  action: "save",
                  requestID: save.requestID,
                  turnID: save.turnID,
                  title: save.title,
                  body: save.body,
                });
                if (!result.entry_id)
                  throw new Error(
                    "This save was previously completed, but that Entry has since been deleted. It was not recreated.",
                  );
                setSavedID(result.entry_id);
                setSave(null);
                await reload();
              });
            }}
          >
            <div className={styles.field}>
              <label htmlFor="conclusion-title">Conclusion title</label>
              <input
                id="conclusion-title"
                value={save.title}
                maxLength={200}
                disabled={busy || save.attempted}
                onChange={(e) => setSave({ ...save, title: e.target.value })}
              />
            </div>
            <div className={styles.field}>
              <label htmlFor="conclusion-text">Conclusion text</label>
              <textarea
                id="conclusion-text"
                value={save.body}
                maxLength={50000}
                rows={8}
                disabled={busy || save.attempted}
                onChange={(e) => setSave({ ...save, body: e.target.value })}
              />
            </div>
            <div className={styles.toolbar}>
              <Button
                variant="primary"
                type="submit"
                disabled={busy || !save.body.trim()}
              >
                {save.attempted ? "Retry same save" : "Save conclusion"}
              </Button>
              <Button
                variant="secondary"
                type="button"
                disabled={busy}
                onClick={() => {
                  void requestConfirmation({
                    title: <>Close this editor?</>,
                    description: (
                      <>
                        If a save was interrupted, refresh the conversation to
                        check whether it was already saved.
                      </>
                    ),
                    confirmLabel: "Close editor",
                    eyebrow: <>Unsaved work</>,
                    variant: "danger",
                  }).then((confirmed) => {
                    if (confirmed) setSave(null);
                  });
                }}
              >
                Cancel
              </Button>
            </div>
          </form>
        </section>
      )}
      {savedID && (
        <p role="status">
          Conclusion saved to Inbox.{" "}
          <Link href={`/items/${savedID}`}>Open saved Entry</Link>
        </p>
      )}
      {error && (
        <p className={styles.error} role="alert">
          {error}
        </p>
      )}
    </>
  );
}
