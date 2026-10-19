"use client";

import { useRef, useState } from "react";
import { Button } from "@/components/button";
import {
  importSourceGuides,
  formatBytes,
  sourceGuide,
} from "@/lib/import/sources";
import type { ImportSource } from "@/lib/import/types";
import styles from "@/components/import-workspace.module.css";

/**
 * The first step: pick the app the export came from, read how to get its ZIP, and choose the
 * file. Nothing leaves the browser until a file is chosen.
 */
export function ImportStart({
  availableSources,
  busy,
  maxBytes,
  onChoose,
}: {
  availableSources: ImportSource[];
  busy: boolean;
  maxBytes: number;
  onChoose: (file: File, source: ImportSource) => void;
}) {
  const guides = importSourceGuides.filter((guide) =>
    availableSources.includes(guide.source),
  );
  const [source, setSource] = useState<ImportSource>(
    guides[0]?.source ?? "markdown",
  );
  const [problem, setProblem] = useState("");
  const input = useRef<HTMLInputElement>(null);
  const guide = sourceGuide(source);

  function choose(file: File | undefined) {
    if (!file) return;
    setProblem("");
    if (!/\.zip$/i.test(file.name) && !file.type.includes("zip")) {
      setProblem(
        "Choose a ZIP file. Compress the export folder first if it is not one.",
      );
      return;
    }
    if (file.size > maxBytes) {
      setProblem(
        `This ZIP is ${formatBytes(file.size)}, over the ${formatBytes(maxBytes)} limit. Export fewer notes at a time and import them in more than one go.`,
      );
      return;
    }
    onChoose(file, source);
  }

  return (
    <>
      <section aria-labelledby="import-source" className={styles.card}>
        <h2 id="import-source">Where are your notes now?</h2>
        <ul className={styles.sourceGrid}>
          {guides.map((item) => (
            <li key={item.source}>
              <button
                aria-pressed={item.source === source}
                className={styles.source}
                onClick={() => setSource(item.source)}
                type="button"
              >
                <strong>{item.name}</strong>
                <span>{item.summary}</span>
              </button>
            </li>
          ))}
        </ul>
      </section>
      {guide ? (
        <section aria-labelledby="import-how" className={styles.card}>
          <h2 id="import-how">Get your {guide.name} ZIP</h2>
          <ol className={styles.steps}>
            {guide.steps.map((step) => (
              <li key={step}>{step}</li>
            ))}
          </ol>
          <ul className={styles.notes}>
            {guide.notes.map((note) => (
              <li key={note}>{note}</li>
            ))}
          </ul>
          <div className={styles.actions}>
            <input
              accept=".zip,application/zip,application/x-zip-compressed"
              aria-label="Choose a ZIP file"
              className={styles.fileInput}
              onChange={(event) => {
                choose(event.target.files?.[0]);
                event.target.value = "";
              }}
              ref={input}
              tabIndex={-1}
              type="file"
            />
            <Button
              disabled={busy}
              onClick={() => input.current?.click()}
              type="button"
              variant="primary"
            >
              Choose ZIP
            </Button>
          </div>
          {problem ? (
            <p className={styles.notice} data-tone="warning" role="alert">
              {problem}
            </p>
          ) : null}
          <p className={styles.footnote}>
            ZIPs up to {formatBytes(maxBytes)} can be imported. The file goes to
            your private space in MemoTrail, is read once, and is removed when
            the import ends. Nothing is sent anywhere else, and no AI reads it.
          </p>
        </section>
      ) : null}
    </>
  );
}
