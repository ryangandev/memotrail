"use client";

import { useId, useRef, useState } from "react";
import { Icon } from "@/components/icon";
import {
  existingTagName,
  tagNameCountLimit,
  tagNameLengthLimit,
} from "@/lib/data/organization";
import styles from "./entry-organization-editor.module.css";

type EntryOrganizationEditorProps = {
  disabled: boolean;
  input: string;
  names: string[];
  onChange: (names: string[]) => void;
  onInputChange: (input: string) => void;
  // The person's tags, most used first.
  options: string[];
};

const limit = { count: tagNameCountLimit, length: tagNameLengthLimit };
// Reusing a tag takes one click, so the most used ones are offered as suggestions.
const suggestionCount = 6;
// The tag count limit is shown only once an Entry gets close to it.
const limitNoticeCount = limit.count - 10;

export function EntryOrganizationEditor({
  disabled,
  input,
  names,
  onChange,
  onInputChange,
  options,
}: EntryOrganizationEditorProps) {
  const editorId = useId();
  const inputRef = useRef<HTMLInputElement>(null);
  const [focused, setFocused] = useState(false);
  const normalizedNames = new Set(
    names.map((name) => name.toLocaleLowerCase()),
  );
  const available = options.filter(
    (option) => !normalizedNames.has(option.toLocaleLowerCase()),
  );
  const full = names.length >= limit.count;
  const query = input.trim();
  const normalizedQuery = query.toLocaleLowerCase();
  const matches = query
    ? available
        .filter((option) =>
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
    !full &&
    !alreadyAddedName;
  const listOpen = focused && Boolean(query);
  // Suggestions stay while a name is typed, so the fields below never jump.
  const suggestions =
    !full && (focused || names.length === 0)
      ? available.slice(0, suggestionCount)
      : [];

  function addName(value: string) {
    const name = existingTagName(value, options);
    if (
      name &&
      name.length <= limit.length &&
      !full &&
      !normalizedNames.has(name.toLocaleLowerCase())
    )
      onChange([...names, name]);
    onInputChange("");
  }

  return (
    <fieldset className={styles.editor} disabled={disabled} data-ui-field>
      <legend id={`${editorId}-label`}>Tags</legend>
      <div
        className={styles.field}
        onBlur={(event) => {
          // A name left in the input stays, and saving the Entry adds it.
          if (!event.currentTarget.contains(event.relatedTarget))
            setFocused(false);
        }}
        onFocus={() => setFocused(true)}
      >
        <div className={styles.combobox}>
          <div
            className={styles.control}
            data-disabled={disabled ? "true" : undefined}
            onMouseDown={(event) => {
              // The whole field focuses the tag input, like a text field.
              if (event.target === event.currentTarget) {
                event.preventDefault();
                inputRef.current?.focus();
              }
            }}
          >
            {names.map((name) => (
              <span className={styles.item} key={name.toLocaleLowerCase()}>
                <span>{`#${name}`}</span>
                <button
                  aria-label={`Remove ${name} from Tags`}
                  className={styles.removeButton}
                  onClick={() =>
                    onChange(names.filter((item) => item !== name))
                  }
                  type="button"
                >
                  <Icon name="close" size={12} />
                </button>
              </span>
            ))}
            <input
              aria-autocomplete="list"
              aria-controls={`${editorId}-options`}
              aria-expanded={listOpen}
              aria-labelledby={`${editorId}-label`}
              autoComplete="off"
              className={styles.input}
              data-escape-layer={query ? "organization" : undefined}
              enterKeyHint="done"
              maxLength={limit.length}
              onChange={(event) => onInputChange(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Escape" && query) {
                  event.preventDefault();
                  event.stopPropagation();
                  onInputChange("");
                }
                if (event.key === "Enter" || event.key === ",") {
                  event.preventDefault();
                  if (canAdd) addName(query);
                  else if (alreadyAddedName) onInputChange("");
                }
                if (event.key === "Backspace" && !input && names.length > 0) {
                  event.preventDefault();
                  onChange(names.slice(0, -1));
                }
              }}
              placeholder={
                full
                  ? "Tag limit reached"
                  : names.length
                    ? "Add another tag"
                    : "Add a tag"
              }
              readOnly={full}
              ref={inputRef}
              role="combobox"
              value={input}
            />
          </div>

          {listOpen ? (
            <div
              className={styles.options}
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
                  <Icon name="tag" size={14} />
                  <span>{alreadyAddedName}</span>
                  <small>Already added</small>
                </div>
              ) : null}
              {matches.map((match) => (
                <button
                  aria-selected="false"
                  key={match.toLocaleLowerCase()}
                  onMouseDown={(event) => event.preventDefault()}
                  onClick={() => addName(match)}
                  role="option"
                  type="button"
                >
                  <Icon name="tag" size={14} />
                  <span>{match}</span>
                  <small>Existing tag</small>
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
                  <span>Create tag</span>
                  <strong>{query}</strong>
                </button>
              ) : null}
            </div>
          ) : null}
        </div>

        {suggestions.length > 0 ? (
          <div
            aria-label="Most used tags"
            className={styles.suggestions}
            role="group"
          >
            <span aria-hidden="true">Most used</span>
            {suggestions.map((suggestion) => (
              <button
                aria-label={`Add tag ${suggestion}`}
                className={styles.suggestion}
                key={suggestion.toLocaleLowerCase()}
                onMouseDown={(event) => event.preventDefault()}
                onClick={() => {
                  addName(suggestion);
                  inputRef.current?.focus();
                }}
                type="button"
              >
                <Icon name="plus" size={12} />
                <span>{suggestion}</span>
              </button>
            ))}
          </div>
        ) : null}
      </div>
      {names.length >= limitNoticeCount ? (
        <small className={styles.limit}>
          {names.length} of {limit.count} tags
        </small>
      ) : null}
    </fieldset>
  );
}
