"use client";

import { useId, useState } from "react";
import { Icon } from "@/components/icon";
import styles from "./entry-organization-editor.module.css";

type EntryOrganizationEditorProps = {
  disabled: boolean;
  input: string;
  kind: "collection" | "tag";
  names: string[];
  onChange: (names: string[]) => void;
  onInputChange: (input: string) => void;
  options: string[];
};

const limits = {
  collection: { count: 20, length: 80 },
  tag: { count: 50, length: 60 },
} as const;

export function EntryOrganizationEditor({
  disabled,
  input,
  kind,
  names,
  onChange,
  onInputChange,
  options,
}: EntryOrganizationEditorProps) {
  const editorId = useId();
  const [open, setOpen] = useState(false);
  const label = kind === "collection" ? "Collections" : "Tags";
  const singular = kind === "collection" ? "Collection" : "tag";
  const limit = limits[kind];
  const normalizedNames = new Set(
    names.map((name) => name.toLocaleLowerCase()),
  );
  const query = input.trim();
  const normalizedQuery = query.toLocaleLowerCase();
  const suggestions = query
    ? options
        .filter(
          (option) =>
            !normalizedNames.has(option.toLocaleLowerCase()) &&
            option.toLocaleLowerCase().includes(normalizedQuery),
        )
        .slice(0, 5)
    : [];
  const exactOption = options.some(
    (option) => option.toLocaleLowerCase() === normalizedQuery,
  );
  const alreadyAddedName = names.find(
    (name) => name.toLocaleLowerCase() === normalizedQuery,
  );
  const canAdd =
    Boolean(query) &&
    query.length <= limit.length &&
    names.length < limit.count &&
    !normalizedNames.has(normalizedQuery);

  function closeEditor() {
    setOpen(false);
    onInputChange("");
  }

  function addName(value: string) {
    const name = value.trim();
    const normalizedName = name.toLocaleLowerCase();

    if (
      !name ||
      name.length > limit.length ||
      names.length >= limit.count ||
      normalizedNames.has(normalizedName)
    ) {
      closeEditor();
      return;
    }

    onChange([...names, name]);
    closeEditor();
  }

  return (
    <fieldset className={styles.editor} data-kind={kind} disabled={disabled}>
      <legend>{label}</legend>
      <div className={styles.items}>
        {names.map((name) => (
          <span className={styles.item} key={name.toLocaleLowerCase()}>
            <span>{kind === "tag" ? `#${name}` : name}</span>
            <button
              aria-label={`Remove ${name} from ${label}`}
              className={styles.removeButton}
              onClick={() => onChange(names.filter((item) => item !== name))}
              type="button"
            >
              <Icon name="close" size={kind === "tag" ? 12 : 13} />
            </button>
          </span>
        ))}

        {open ? (
          <div
            className={styles.inlineEditor}
            onBlur={(event) => {
              if (!event.currentTarget.contains(event.relatedTarget)) {
                closeEditor();
              }
            }}
          >
            <div className={styles.inputShell}>
              <Icon name={kind === "tag" ? "tag" : "archive"} size={14} />
              <input
                data-escape-layer="organization"
                aria-controls={`${editorId}-options`}
                aria-expanded={Boolean(query)}
                aria-label={`Search or create a ${singular}`}
                autoFocus
                maxLength={limit.length}
                onChange={(event) => onInputChange(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === "Escape") {
                    event.preventDefault();
                    event.stopPropagation();
                    closeEditor();
                  }
                  if (
                    event.key === "Enter" ||
                    (kind === "tag" && event.key === ",")
                  ) {
                    event.preventDefault();
                    if (canAdd) addName(query);
                  }
                }}
                placeholder={`Find or create ${singular.toLowerCase()}`}
                role="combobox"
                value={input}
              />
            </div>
            {query ? (
              <div
                className={styles.suggestions}
                id={`${editorId}-options`}
                role="listbox"
              >
                {alreadyAddedName ? (
                  <div
                    aria-disabled="true"
                    aria-selected="false"
                    className={styles.statusOption}
                    role="option"
                  >
                    <Icon name={kind === "tag" ? "tag" : "archive"} size={14} />
                    <span>{alreadyAddedName}</span>
                    <small>Already added</small>
                  </div>
                ) : null}
                {suggestions.map((suggestion) => (
                  <button
                    aria-selected="false"
                    key={suggestion.toLocaleLowerCase()}
                    onMouseDown={(event) => event.preventDefault()}
                    onClick={() => addName(suggestion)}
                    role="option"
                    type="button"
                  >
                    <Icon name={kind === "tag" ? "tag" : "archive"} size={14} />
                    <span>{suggestion}</span>
                    <small>Existing {singular.toLowerCase()}</small>
                  </button>
                ))}
                {canAdd && !exactOption ? (
                  <button
                    aria-selected="false"
                    className={styles.createOption}
                    onMouseDown={(event) => event.preventDefault()}
                    onClick={() => addName(query)}
                    role="option"
                    type="button"
                  >
                    <Icon name="plus" size={14} />
                    <span>Create {singular.toLowerCase()}</span>
                    <strong>{query}</strong>
                  </button>
                ) : null}
              </div>
            ) : null}
          </div>
        ) : names.length < limit.count ? (
          <button
            aria-label={`Add ${singular}`}
            className={styles.addButton}
            onClick={() => setOpen(true)}
            type="button"
          >
            <Icon name="plus" size={15} />
            <span>Add {singular}</span>
          </button>
        ) : null}
      </div>
      <small>
        {names.length} of {limit.count}
      </small>
    </fieldset>
  );
}
