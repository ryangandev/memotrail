"use client";

import { useEffect, useMemo, useState, type CSSProperties } from "react";
import { Button } from "@/components/button";
import { Checkbox } from "@/components/checkbox";
import { SelectField } from "@/components/select-field";
import { TimezoneSelect } from "@/components/timezone-select";
import { countLabel } from "@/lib/count-label";
import type { ImportJobView, ImportSample } from "@/lib/import/contracts";
import { importRequest } from "@/lib/import/client";
import { importLabels, sourceLabel } from "@/lib/import/labels";
import { detectionAgrees, formatBytes } from "@/lib/import/sources";
import { importMarkerTag } from "@/lib/import/tags";
import type { ImportOptions } from "@/lib/import/types";
import styles from "@/components/import-workspace.module.css";

type PreviewResponse = {
  defaults: ImportOptions;
  job: ImportJobView;
  sample: ImportSample[];
};

const pathKey = (path: string[]) => JSON.stringify(path);

function day(value: string) {
  return new Intl.DateTimeFormat("en-US", {
    dateStyle: "medium",
    timeZone: "UTC",
  }).format(new Date(`${value}T12:00:00Z`));
}

/**
 * Everything the scan found, before anything is written: totals, folders to leave out, the
 * choices that shape each Entry, and a sample of what Entries will look like.
 */
export function ImportPreview({
  busy,
  job,
  onCancel,
  onConfirm,
}: {
  busy: boolean;
  job: ImportJobView;
  onCancel: () => void;
  onConfirm: (options: ImportOptions, excludedFolders: string[][]) => void;
}) {
  const [data, setData] = useState<PreviewResponse | null>(null);
  const [options, setOptions] = useState<ImportOptions | null>(null);
  const [excluded, setExcluded] = useState<Set<string>>(new Set());
  const [warningsOnly, setWarningsOnly] = useState(false);
  const [error, setError] = useState("");
  const [allowMismatch, setAllowMismatch] = useState(false);
  const timezone = options?.timezone ?? null;
  const notionDateProperty = options?.notionDateProperty ?? null;

  useEffect(() => {
    const controller = new AbortController();
    importRequest<PreviewResponse>(
      {
        action: "preview",
        jobId: job.id,
        notionDateProperty,
        timezone,
        warningsOnly,
      },
      controller.signal,
    ).then(
      (response) => {
        setData(response);
        setOptions((current) => current ?? response.defaults);
        setError("");
      },
      (reason) => {
        if (!controller.signal.aborted)
          setError(
            reason instanceof Error
              ? reason.message
              : "The preview could not load. Try again.",
          );
      },
    );
    return () => controller.abort();
  }, [job.id, notionDateProperty, timezone, warningsOnly]);

  const totals = data?.job.totals ?? job.totals;
  const folders = useMemo(() => totals.folders ?? [], [totals.folders]);
  const mismatch = !detectionAgrees(job.source, totals.detected);

  const isExcluded = (path: string[]) =>
    path.some((_, index) => excluded.has(pathKey(path.slice(0, index + 1))));

  const selectedEntries = useMemo(() => {
    const total = totals.entries ?? 0;
    let removed = 0;
    for (const folder of folders) {
      const parentExcluded = folder.path
        .slice(0, -1)
        .some((_, index) =>
          excluded.has(pathKey(folder.path.slice(0, index + 1))),
        );
      if (excluded.has(pathKey(folder.path)) && !parentExcluded)
        removed += folder.entries;
    }
    return Math.max(0, total - removed);
  }, [excluded, folders, totals.entries]);

  function toggleFolder(path: string[]) {
    setExcluded((current) => {
      const next = new Set(current);
      const key = pathKey(path);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }

  if (!options || !data)
    return (
      <section className={styles.card} aria-live="polite">
        <h2>Looking through your export</h2>
        <p>{error || "Preparing a preview of what will be imported."}</p>
      </section>
    );

  const overlap = data.job.totals.overlap;
  const marker = importMarkerTag(job.source);
  const setTags = (patch: Partial<ImportOptions["tags"]>) =>
    setOptions({ ...options, tags: { ...options.tags, ...patch } });
  const properties = totals.notionDateProperties ?? [];
  const canStart = selectedEntries > 0 && (!mismatch || allowMismatch) && !busy;

  return (
    <>
      <section aria-labelledby="import-found" className={styles.card}>
        <h2 id="import-found">
          Found {countLabel(totals.entries ?? 0, "Entry")} in {job.fileName}
        </h2>
        <dl className={styles.stats}>
          <div className={styles.stat}>
            <dt>Entries</dt>
            <dd>{totals.entries ?? 0}</dd>
          </div>
          <div className={styles.stat}>
            <dt>Photos</dt>
            <dd>
              {totals.photos ?? 0}
              {totals.photoBytes ? ` · ${formatBytes(totals.photoBytes)}` : ""}
            </dd>
          </div>
          <div className={styles.stat}>
            <dt>Dates</dt>
            <dd>
              {totals.dateRange
                ? totals.dateRange.from === totals.dateRange.to
                  ? day(totals.dateRange.from)
                  : `${day(totals.dateRange.from)} to ${day(totals.dateRange.to)}`
                : "None found"}
            </dd>
          </div>
          <div className={styles.stat}>
            <dt>Without a date</dt>
            <dd>{totals.undated ?? 0}</dd>
          </div>
        </dl>
        {mismatch ? (
          <div className={styles.notice} data-tone="warning" role="alert">
            <p>
              This does not look like a {sourceLabel(job.source)} export. It
              looks more like {sourceLabel(totals.detected!.source)}. Importing
              it anyway may leave out dates or photos.
            </p>
            <Checkbox
              checked={allowMismatch}
              label="Import it anyway"
              onChange={(event) => setAllowMismatch(event.target.checked)}
            />
          </div>
        ) : null}
        {(totals.undated ?? 0) > 0 ? (
          <p>
            {countLabel(totals.undated ?? 0, "Entry")}{" "}
            {totals.undated === 1 ? "has" : "have"} no date in the export.{" "}
            {totals.undated === 1 ? "It is" : "They are"} imported without one
            rather than given a date that did not happen
            {totals.unparsedDates
              ? `, including ${totals.unparsedDates} whose date could not be read`
              : ""}
            .
          </p>
        ) : null}
        {(totals.skippedResources?.length ?? 0) > 0 ||
        Object.keys(totals.skippedItems ?? {}).length > 0 ? (
          <div>
            <p>MemoTrail keeps text and photos, so these are left out:</p>
            <ul className={styles.breakdown}>
              {totals.skippedResources?.map((skipped) => (
                <li key={skipped.kind}>
                  {skipped.count}{" "}
                  {importLabels.skippedKinds[skipped.kind] ?? skipped.kind}
                </li>
              ))}
              {Object.entries(totals.skippedItems ?? {}).map(
                ([reason, count]) => (
                  <li key={reason}>
                    {countLabel(count, "note")}:{" "}
                    {(importLabels.reasons[reason] ?? reason).toLowerCase()}
                  </li>
                ),
              )}
            </ul>
          </div>
        ) : null}
        {overlap &&
        (overlap.unchanged > 0 ||
          overlap.changed > 0 ||
          overlap.inTrash > 0) ? (
          <div className={styles.notice} role="status">
            <p>
              {overlap.unchanged > 0
                ? `${countLabel(overlap.unchanged, "Entry")} from this export ${overlap.unchanged === 1 ? "is" : "are"} already in MemoTrail and will be skipped. `
                : ""}
              {overlap.changed > 0
                ? `${overlap.changed} changed in the source since you imported them. They stay as they are here so your edits are safe. `
                : ""}
              {overlap.inTrash > 0
                ? `${overlap.inTrash} ${overlap.inTrash === 1 ? "is" : "are"} in Trash and will stay there.`
                : ""}
            </p>
          </div>
        ) : null}
      </section>

      {folders.length > 0 ? (
        <section aria-labelledby="import-folders" className={styles.card}>
          <h2 id="import-folders">Folders</h2>
          <p>Uncheck a folder to leave everything in it out of this import.</p>
          <ul className={styles.folderList}>
            {folders.map((folder) => {
              const off = isExcluded(folder.path);
              const inherited = off && !excluded.has(pathKey(folder.path));
              return (
                <li
                  data-excluded={off}
                  key={pathKey(folder.path)}
                  style={{ "--depth": folder.path.length - 1 } as CSSProperties}
                >
                  <Checkbox
                    checked={!off}
                    description={`${countLabel(folder.entries, "Entry")}${folder.photos ? `, ${countLabel(folder.photos, "photo")}` : ""}`}
                    disabled={inherited}
                    label={folder.path.at(-1)}
                    onChange={() => toggleFolder(folder.path)}
                    size="small"
                  />
                </li>
              );
            })}
          </ul>
          {totals.foldersTruncated ? (
            <p className={styles.footnote}>
              This export has more folders than can be listed. Folders beyond
              the list are imported.
            </p>
          ) : null}
        </section>
      ) : null}

      <section aria-labelledby="import-options" className={styles.card}>
        <h2 id="import-options">How to import</h2>
        <div className={styles.options}>
          <div className={styles.optionGroup}>
            <label className={styles.fieldLabel}>
              Time zone for dates without one
              <TimezoneSelect
                ariaLabel="Time zone for dates without one"
                onChange={(event) =>
                  setOptions({ ...options, timezone: event.target.value })
                }
                value={options.timezone}
              />
            </label>
            <SelectField
              label="Entries without a date"
              onChange={(event) =>
                setOptions({
                  ...options,
                  undated: event.target.value as ImportOptions["undated"],
                })
              }
              value={options.undated}
            >
              <option value="leave">Leave them without a date</option>
              <option value="file_time">
                Use the date each file was last changed
              </option>
            </SelectField>
            {properties.length > 0 ? (
              <SelectField
                label="Notion date property"
                onChange={(event) =>
                  setOptions({
                    ...options,
                    notionDateProperty: event.target.value || null,
                  })
                }
                value={options.notionDateProperty ?? ""}
              >
                <option value="">Do not use a property</option>
                {properties.map((property) => (
                  <option key={property} value={property}>
                    {property}
                  </option>
                ))}
              </SelectField>
            ) : null}
          </div>
          <fieldset className={styles.optionGroup}>
            <legend>Tags</legend>
            <Checkbox
              checked={options.tags.marker}
              description="One tag lists everything from this import, and Library can filter on it."
              label={`Tag every Entry "${marker}"`}
              onChange={(event) => setTags({ marker: event.target.checked })}
            />
            <Checkbox
              checked={options.tags.source}
              label="Keep tags from the export"
              onChange={(event) => setTags({ source: event.target.checked })}
            />
            {job.source === "notion" ? (
              <Checkbox
                checked={options.tags.properties}
                label="Use Notion tag properties as tags"
                onChange={(event) =>
                  setTags({ properties: event.target.checked })
                }
              />
            ) : null}
            <Checkbox
              checked={options.tags.folders}
              description={
                (totals.distinctParentFolders ?? 0) > 30
                  ? `Off by default: this would add ${totals.distinctParentFolders} folder tags.`
                  : "Each Entry gets the name of the folder it was in."
              }
              label="Tag Entries with their folder name"
              onChange={(event) => setTags({ folders: event.target.checked })}
            />
          </fieldset>
        </div>
      </section>

      <section aria-labelledby="import-sample" className={styles.card}>
        <h2 id="import-sample">What Entries will look like</h2>
        <Checkbox
          checked={warningsOnly}
          label="Only show Entries with something to check"
          onChange={(event) => setWarningsOnly(event.target.checked)}
        />
        {data.sample.length === 0 ? (
          <p>
            {warningsOnly
              ? "No Entry has anything to check."
              : "There are no Entries to show."}
          </p>
        ) : (
          <ul className={styles.samples}>
            {data.sample.map((entry) => (
              <li className={styles.sample} key={entry.sourceKey}>
                <h4>{entry.title ?? "Untitled"}</h4>
                <div className={styles.sampleMeta}>
                  <span>{entry.dateLabel}</span>
                  {entry.folderPath.length > 0 ? (
                    <span>{entry.folderPath.join(" / ")}</span>
                  ) : null}
                  {entry.photoCount > 0 ? (
                    <span>{countLabel(entry.photoCount, "photo")}</span>
                  ) : null}
                  {entry.tagNames.map((tag) => (
                    <span key={tag}>#{tag}</span>
                  ))}
                </div>
                {entry.text ? <p>{entry.text}</p> : null}
                {entry.warnings.map((warning) => (
                  <span className={styles.sampleWarning} key={warning}>
                    {importLabels.warnings[warning] ?? warning}
                  </span>
                ))}
              </li>
            ))}
          </ul>
        )}
      </section>

      {error ? (
        <p className={styles.notice} data-tone="danger" role="alert">
          {error}
        </p>
      ) : null}
      <div className={styles.actions}>
        <Button
          disabled={!canStart}
          loading={busy}
          onClick={() =>
            onConfirm(
              options,
              [...excluded].map((key) => JSON.parse(key) as string[]),
            )
          }
          variant="primary"
        >
          {selectedEntries > 0
            ? `Import ${countLabel(selectedEntries, "Entry")}`
            : "Nothing selected"}
        </Button>
        <Button disabled={busy} onClick={onCancel} variant="secondary">
          Cancel
        </Button>
      </div>
      <p className={styles.footnote}>
        Entries are added to your Library as ordinary Entries. Nothing is
        changed until you choose Import, and you can undo the whole import for
        30 days.
      </p>
    </>
  );
}
