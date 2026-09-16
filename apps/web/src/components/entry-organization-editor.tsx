"use client";

import { useId } from "react";
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
  const datalistId = useId();
  const label = kind === "collection" ? "Collections" : "Tags";
  const limit = limits[kind];
  const normalizedNames = new Set(
    names.map((name) => name.toLocaleLowerCase()),
  );
  const suggestions = options.filter(
    (option) => !normalizedNames.has(option.toLocaleLowerCase()),
  );

  function addName(value: string) {
    const name = value.trim();

    if (
      !name ||
      name.length > limit.length ||
      names.length >= limit.count ||
      normalizedNames.has(name.toLocaleLowerCase())
    ) {
      onInputChange("");
      return;
    }

    onChange([...names, name]);
    onInputChange("");
  }

  return (
    <fieldset className={styles.editor} disabled={disabled}>
      <legend>{label}</legend>
      <p className={styles.guidance}>
        {kind === "collection"
          ? "Add this item to a larger story or chapter."
          : "Add specific descriptors for filtering and discovery."}
      </p>
      {names.length > 0 ? (
        <div className={styles.chips}>
          {names.map((name) => (
            <button
              aria-label={`Remove ${name} from ${label}`}
              key={name.toLocaleLowerCase()}
              onClick={() => onChange(names.filter((item) => item !== name))}
              type="button"
            >
              {kind === "tag" ? `#${name}` : name}
              <span aria-hidden="true">×</span>
            </button>
          ))}
        </div>
      ) : null}
      <input
        aria-label={`Add ${kind === "collection" ? "a Collection" : "a tag"}`}
        list={datalistId}
        maxLength={limit.length}
        onBlur={() => {
          if (input.trim()) addName(input);
        }}
        onChange={(event) => onInputChange(event.target.value)}
        onKeyDown={(event) => {
          if (event.key === "Enter" || event.key === ",") {
            event.preventDefault();
            addName(input);
          }
        }}
        placeholder={`Add ${kind === "collection" ? "a Collection" : "a tag"}`}
        value={input}
      />
      <datalist id={datalistId}>
        {suggestions.map((suggestion) => (
          <option key={suggestion.toLocaleLowerCase()} value={suggestion} />
        ))}
      </datalist>
      <small>
        {names.length} of {limit.count}
      </small>
    </fieldset>
  );
}
