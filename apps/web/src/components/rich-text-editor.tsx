"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import {
  EditorContent,
  useEditor,
  useEditorState,
  type Editor,
} from "@tiptap/react";
import StarterKit from "@tiptap/starter-kit";
import { CharacterCount, Placeholder } from "@tiptap/extensions";
import { Icon, type IconName } from "@/components/icon";
import {
  createEntryRichText,
  plainTextDocument,
  type EntryRichText,
  type RichTextDocument,
} from "@/lib/data/rich-text";
import styles from "./rich-text-editor.module.css";

type RichTextEditorProps = {
  autoFocus?: boolean;
  disabled?: boolean;
  label: string;
  maxLength: number;
  onChange: (value: EntryRichText) => void;
  placeholder: string;
  richText: EntryRichText | null;
  text: string;
  variant?: "compact" | "form";
};

type FormatState = {
  blockquote: boolean;
  bold: boolean;
  bulletList: boolean;
  code: boolean;
  codeBlock: boolean;
  italic: boolean;
  link: boolean;
  orderedList: boolean;
  strike: boolean;
  underline: boolean;
};

const emptyFormatState: FormatState = {
  blockquote: false,
  bold: false,
  bulletList: false,
  code: false,
  codeBlock: false,
  italic: false,
  link: false,
  orderedList: false,
  strike: false,
  underline: false,
};

export function RichTextEditor({
  autoFocus = false,
  disabled = false,
  label,
  maxLength,
  onChange,
  placeholder,
  richText,
  text,
  variant = "form",
}: RichTextEditorProps) {
  const onChangeRef = useRef(onChange);
  const textRef = useRef(text);
  const didAutoFocusRef = useRef(false);
  const extensions = useMemo(
    () => [
      StarterKit.configure({
        heading: false,
        horizontalRule: false,
        link: {
          HTMLAttributes: {
            rel: "noopener noreferrer",
            target: "_blank",
          },
          defaultProtocol: "https",
          enableClickSelection: true,
          isAllowedUri: (url, context) =>
            context.defaultValidate(url) && Boolean(normalizedLink(url)),
          openOnClick: false,
          protocols: ["mailto", "tel"],
        },
      }),
      CharacterCount.configure({ limit: maxLength }),
      Placeholder.configure({ placeholder }),
    ],
    [maxLength, placeholder],
  );
  const editor = useEditor(
    {
      content:
        richText?.text === text ? richText.document : plainTextDocument(text),
      editable: !disabled,
      editorProps: {
        attributes: {
          "aria-label": label,
          "aria-multiline": "true",
          role: "textbox",
          spellcheck: "true",
        },
      },
      extensions,
      immediatelyRender: false,
      onUpdate: ({ editor: updatedEditor }) => {
        const value = createEntryRichText(
          updatedEditor.getJSON() as RichTextDocument,
        );
        if (value) {
          textRef.current = value.text;
          onChangeRef.current(value);
          return;
        }

        updatedEditor.commands.setContent(plainTextDocument(textRef.current), {
          emitUpdate: false,
        });
      },
    },
    [extensions, label],
  );

  useEffect(() => {
    onChangeRef.current = onChange;
  }, [onChange]);

  useEffect(() => {
    textRef.current = text;
  }, [text]);

  useEffect(() => {
    editor?.setEditable(!disabled);
  }, [disabled, editor]);

  useEffect(() => {
    if (!editor) return;
    const desired =
      richText?.text === text ? richText.document : plainTextDocument(text);
    if (JSON.stringify(editor.getJSON()) !== JSON.stringify(desired)) {
      editor.commands.setContent(desired, { emitUpdate: false });
    }
  }, [editor, richText, text]);

  useEffect(() => {
    if (!editor || !autoFocus || disabled || didAutoFocusRef.current) return;
    didAutoFocusRef.current = true;
    editor.commands.focus("end");
  }, [autoFocus, disabled, editor]);

  return (
    <div
      className={`${styles.editor} ${variant === "compact" ? styles.compact : styles.form}`}
      data-rich-text-editor
    >
      <EditorContent className={styles.content} editor={editor} />
      <FormattingToolbar disabled={disabled} editor={editor} />
    </div>
  );
}

function FormattingToolbar({
  disabled,
  editor,
}: {
  disabled: boolean;
  editor: Editor | null;
}) {
  const [isLinkEditorOpen, setIsLinkEditorOpen] = useState(false);
  const [linkValue, setLinkValue] = useState("");
  const linkInputRef = useRef<HTMLInputElement>(null);
  const formatState =
    useEditorState({
      editor,
      selector: ({ editor: current }) =>
        current
          ? {
              blockquote: current.isActive("blockquote"),
              bold: current.isActive("bold"),
              bulletList: current.isActive("bulletList"),
              code: current.isActive("code"),
              codeBlock: current.isActive("codeBlock"),
              italic: current.isActive("italic"),
              link: current.isActive("link"),
              orderedList: current.isActive("orderedList"),
              strike: current.isActive("strike"),
              underline: current.isActive("underline"),
            }
          : emptyFormatState,
    }) ?? emptyFormatState;

  useEffect(() => {
    if (isLinkEditorOpen) linkInputRef.current?.focus();
  }, [isLinkEditorOpen]);

  function openLinkEditor() {
    if (!editor) return;
    setLinkValue((editor.getAttributes("link").href as string | undefined) ?? "");
    setIsLinkEditorOpen(true);
  }

  function applyLink() {
    if (!editor) return;
    const href = normalizedLink(linkValue);
    if (!href) return;
    editor.chain().focus().extendMarkRange("link").setLink({ href }).run();
    setIsLinkEditorOpen(false);
  }

  function removeLink() {
    editor?.chain().focus().extendMarkRange("link").unsetLink().run();
    setIsLinkEditorOpen(false);
  }

  return (
    <div className={styles.toolbar} aria-label="Text formatting" role="toolbar">
      <ToolbarButton
        active={formatState.bold}
        disabled={disabled || !editor}
        icon="bold"
        label="Bold"
        onRun={() => editor?.chain().focus().toggleBold().run()}
      />
      <ToolbarButton
        active={formatState.italic}
        disabled={disabled || !editor}
        icon="italic"
        label="Italic"
        onRun={() => editor?.chain().focus().toggleItalic().run()}
      />
      <ToolbarButton
        active={formatState.underline}
        disabled={disabled || !editor}
        icon="underline"
        label="Underline"
        onRun={() => editor?.chain().focus().toggleUnderline().run()}
      />
      <ToolbarButton
        active={formatState.strike}
        disabled={disabled || !editor}
        icon="strike"
        label="Strikethrough"
        onRun={() => editor?.chain().focus().toggleStrike().run()}
      />
      <ToolbarButton
        active={formatState.link}
        disabled={disabled || !editor}
        icon="link"
        label="Attach link"
        onRun={openLinkEditor}
      />
      <span className={styles.separator} role="separator" />
      <ToolbarButton
        active={formatState.bulletList}
        disabled={disabled || !editor}
        icon="bulletList"
        label="Bullet list"
        onRun={() => editor?.chain().focus().toggleBulletList().run()}
      />
      <ToolbarButton
        active={formatState.orderedList}
        disabled={disabled || !editor}
        icon="orderedList"
        label="Ordered list"
        onRun={() => editor?.chain().focus().toggleOrderedList().run()}
      />
      <ToolbarButton
        active={formatState.blockquote}
        disabled={disabled || !editor}
        icon="quote"
        label="Block quote"
        onRun={() => editor?.chain().focus().toggleBlockquote().run()}
      />
      <span className={styles.separator} role="separator" />
      <ToolbarButton
        active={formatState.code}
        disabled={disabled || !editor || formatState.codeBlock}
        icon="code"
        label="Inline code"
        onRun={() => editor?.chain().focus().toggleCode().run()}
      />
      <ToolbarButton
        active={formatState.codeBlock}
        disabled={disabled || !editor}
        icon="codeBlock"
        label="Code block"
        onRun={() => editor?.chain().focus().toggleCodeBlock().run()}
      />

      {isLinkEditorOpen ? (
        <div className={styles.linkEditor} role="group" aria-label="Link editor">
          <input
            aria-label="Link URL"
            onChange={(event) => setLinkValue(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Enter") {
                event.preventDefault();
                applyLink();
              }
              if (event.key === "Escape") {
                event.preventDefault();
                setIsLinkEditorOpen(false);
                editor?.commands.focus();
              }
            }}
            placeholder="https://example.com"
            ref={linkInputRef}
            type="url"
            value={linkValue}
          />
          {formatState.link ? (
            <button onClick={removeLink} type="button">
              Remove
            </button>
          ) : null}
          <button
            onClick={() => {
              setIsLinkEditorOpen(false);
              editor?.commands.focus();
            }}
            type="button"
          >
            Cancel
          </button>
          <button disabled={!normalizedLink(linkValue)} onClick={applyLink} type="button">
            Apply
          </button>
        </div>
      ) : null}
    </div>
  );
}

function ToolbarButton({
  active,
  disabled,
  icon,
  label,
  onRun,
}: {
  active: boolean;
  disabled: boolean;
  icon: IconName;
  label: string;
  onRun: () => void;
}) {
  return (
    <button
      aria-label={label}
      aria-pressed={active}
      className={`${styles.toolbarButton} ${active ? styles.active : ""}`}
      disabled={disabled}
      onClick={onRun}
      onMouseDown={(event) => event.preventDefault()}
      title={label}
      type="button"
    >
      <Icon name={icon} size={17} />
    </button>
  );
}

function normalizedLink(value: string) {
  const trimmed = value.trim();
  if (!trimmed) return null;
  const candidate = /^[a-z][a-z\d+.-]*:/i.test(trimmed)
    ? trimmed
    : `https://${trimmed}`;

  try {
    const url = new URL(candidate);
    return ["http:", "https:", "mailto:", "tel:"].includes(url.protocol)
      ? url.toString()
      : null;
  } catch {
    return null;
  }
}
