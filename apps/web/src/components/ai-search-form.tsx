"use client";
import Link from "next/link";
import { useRef, useState, type ReactNode, type FormEvent } from "react";
import type { AISearchResponse } from "@/lib/ai/search";
import styles from "./ai-search-form.module.css";

export function AISearchForm({
  children,
  keywordResults,
}: {
  children: ReactNode;
  keywordResults: ReactNode;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [answer, setAnswer] = useState<AISearchResponse | null>(null);
  const active = useRef(false);
  async function submit(event: FormEvent<HTMLFormElement>) {
    const submitter = (event.nativeEvent as SubmitEvent).submitter;
    if (!(submitter instanceof HTMLButtonElement) || submitter.value !== "ai")
      return;
    event.preventDefault();
    if (active.current) return;
    const data = new FormData(event.currentTarget);
    const parameters = Object.fromEntries(
      ["q", "type", "collection", "tag", "from", "to"].map((k) => [
        k,
        data.getAll(k).map(String),
      ]),
    );
    if (!parameters.q?.[0]?.trim()) {
      setError("Enter a question in the search field first.");
      return;
    }
    active.current = true;
    setBusy(true);
    setError(null);
    setAnswer(null);
    try {
      const response = await fetch("/api/ai/search", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          parameters,
          timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
        }),
        signal: AbortSignal.timeout(95_000),
      });
      const result = await response.json();
      if (!response.ok)
        throw new Error(result.error || "AI search is unavailable.");
      setAnswer(result);
    } catch (e) {
      setError(
        e instanceof Error && e.name !== "TimeoutError"
          ? e.message
          : "AI search was interrupted. There is no automatic retry; your records are unchanged.",
      );
    } finally {
      active.current = false;
      setBusy(false);
    }
  }
  return (
    <>
      <form
        action="/search"
        method="get"
        onSubmit={submit}
        onChange={() => {
          setAnswer(null);
          setError(null);
        }}
      >
        <fieldset className={styles.fields} disabled={busy}>
          {children}
          <div className={styles.actions}>
            <p>
              Uses this search field and its filters. Sends the question and
              relevant text to Anthropic only when you ask.{" "}
              <Link href="/settings/ai">AI settings</Link>
            </p>
          </div>
        </fieldset>
      </form>
      {busy && (
        <p className={styles.notice} role="status">
          Searching your archive. This can take up to a minute. Your original
          records stay unchanged.
        </p>
      )}
      {error && (
        <p className={styles.notice} role="alert">
          {error}
        </p>
      )}
      {answer ? (
        <section className={styles.answer} aria-label="AI search answer">
          <header>
            <p className={styles.eyebrow}>
              AI-assisted search · check the sources
            </p>
            <h2>{answer.question}</h2>
          </header>
          {answer.insufficientEvidence && (
            <p role="status">
              {answer.findings.length
                ? "The retrieved records only partly answer this question."
                : "Not enough evidence in the retrieved records to answer this question. Try different words or filters."}
            </p>
          )}
          {answer.findings.map((finding, i) => (
            <article key={i} className={styles.finding}>
              <p>{finding.text}</p>
              {finding.citations.map((citation, n) => {
                const source = answer.sources.find(
                  (s) => s.id === citation.sourceID,
                )!;
                return (
                  <div key={n} className={styles.citation}>
                    {citation.quote.startsWith("Recorded facts:") ? (
                      <details className={styles.facts}>
                        <summary>Recorded facts</summary>
                        <blockquote>{citation.quote}</blockquote>
                      </details>
                    ) : (
                      <blockquote>{citation.quote}</blockquote>
                    )}
                    <Link
                      href={source.href ?? `#evidence-${source.id}`}
                      onClick={() => {
                        if (!source.href) {
                          const details = document
                            .getElementById(`evidence-${source.id}`)
                            ?.closest("details");
                          if (details) details.open = true;
                        }
                      }}
                    >
                      {source.title}
                    </Link>
                  </div>
                );
              })}
            </article>
          ))}
          {answer.notices.map((notice) => (
            <p key={notice} className={styles.notice}>
              {notice}
            </p>
          ))}
          <details className={styles.sources}>
            <summary>Retrieved sources ({answer.sources.length})</summary>
            {answer.sources.map((source) => (
              <article
                id={`evidence-${source.id}`}
                key={source.id}
                tabIndex={-1}
              >
                <h3>{source.title}</h3>
                <p>
                  {source.kind}
                  {source.truncated ? " · excerpt" : ""}
                </p>
                <pre>{source.text}</pre>
                {source.href && (
                  <Link href={source.href}>Open original record</Link>
                )}
              </article>
            ))}
          </details>
          <p className={styles.notice}>
            AI interpretations can be wrong. Retrieval uses query expansion and
            bounded text matching, not a complete vector index. Nothing is saved
            as an Entry.
          </p>
        </section>
      ) : (
        !busy && keywordResults
      )}
    </>
  );
}
