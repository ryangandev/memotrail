"use client";

import {
  useCallback,
  useEffect,
  useId,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from "react";
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
  variant?: "dialog" | "form" | "page";
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
        handleKeyDown: (view, event) => {
          const shortcut = formattingShortcut(event);
          if (!shortcut) return false;
          event.preventDefault();
          view.dom.dispatchEvent(
            new CustomEvent(formattingShortcutEvent, { detail: shortcut }),
          );
          return true;
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
      className={`${styles.editor} ${variantClassNames[variant]}`}
      data-disabled={disabled || undefined}
      data-rich-text-editor
      data-variant={variant}
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

  useLayoutEffect(() => {
    if (isLinkEditorOpen) linkInputRef.current?.focus();
  }, [isLinkEditorOpen]);

  const openLinkEditor = useCallback(() => {
    if (!editor) return;
    setLinkValue(
      (editor.getAttributes("link").href as string | undefined) ?? "",
    );
    setIsLinkEditorOpen(true);
  }, [editor]);

  useEffect(() => {
    if (!editor) return;
    const currentEditor = editor;
    const element = currentEditor.view.dom;

    function handleEditorShortcut(event: Event) {
      const shortcut = (event as CustomEvent<FormattingShortcut>).detail;
      if (shortcut === "link") {
        openLinkEditor();
        return;
      }

      if (shortcut === "orderedList") {
        currentEditor.chain().focus().toggleOrderedList().run();
        return;
      }

      if (shortcut === "bulletList") {
        currentEditor.chain().focus().toggleBulletList().run();
      }
    }

    element.addEventListener(formattingShortcutEvent, handleEditorShortcut);
    return () =>
      element.removeEventListener(
        formattingShortcutEvent,
        handleEditorShortcut,
      );
  }, [editor, openLinkEditor]);

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
        ariaKeyShortcuts="Meta+B Control+B"
        disabled={disabled || !editor}
        icon="bold"
        label="Bold"
        onRun={() => editor?.chain().focus().toggleBold().run()}
        shortcut="⌘B"
      />
      <ToolbarButton
        active={formatState.italic}
        ariaKeyShortcuts="Meta+I Control+I"
        disabled={disabled || !editor}
        icon="italic"
        label="Italic"
        onRun={() => editor?.chain().focus().toggleItalic().run()}
        shortcut="⌘I"
      />
      <ToolbarButton
        active={formatState.underline}
        ariaKeyShortcuts="Meta+U Control+U"
        disabled={disabled || !editor}
        icon="underline"
        label="Underline"
        onRun={() => editor?.chain().focus().toggleUnderline().run()}
        shortcut="⌘U"
      />
      <ToolbarButton
        active={formatState.strike}
        ariaKeyShortcuts="Meta+Shift+S Control+Shift+S"
        disabled={disabled || !editor}
        icon="strike"
        label="Strikethrough"
        onRun={() => editor?.chain().focus().toggleStrike().run()}
        shortcut="⌘⇧S"
      />
      <ToolbarButton
        active={formatState.link}
        ariaKeyShortcuts="Meta+K Control+K"
        disabled={disabled || !editor}
        icon="link"
        label="Attach link"
        onRun={openLinkEditor}
        shortcut="⌘K"
      />
      <span className={styles.separator} role="separator" />
      <ToolbarButton
        active={formatState.bulletList}
        ariaKeyShortcuts="Meta+Shift+8 Control+Shift+8"
        disabled={disabled || !editor}
        icon="bulletList"
        label="Bullet list"
        onRun={() => editor?.chain().focus().toggleBulletList().run()}
        shortcut="⌘⇧8"
      />
      <ToolbarButton
        active={formatState.orderedList}
        ariaKeyShortcuts="Meta+Shift+7 Control+Shift+7"
        disabled={disabled || !editor}
        icon="orderedList"
        label="Ordered list"
        onRun={() => editor?.chain().focus().toggleOrderedList().run()}
        shortcut="⌘⇧7"
      />
      <ToolbarButton
        active={formatState.blockquote}
        ariaKeyShortcuts="Meta+Shift+B Control+Shift+B"
        disabled={disabled || !editor}
        icon="quote"
        label="Block quote"
        onRun={() => editor?.chain().focus().toggleBlockquote().run()}
        shortcut="⌘⇧B"
      />
      <span className={styles.separator} role="separator" />
      <ToolbarButton
        active={formatState.code}
        ariaKeyShortcuts="Meta+E Control+E"
        disabled={disabled || !editor || formatState.codeBlock}
        icon="code"
        label="Inline code"
        onRun={() => editor?.chain().focus().toggleCode().run()}
        shortcut="⌘E"
      />
      <ToolbarButton
        active={formatState.codeBlock}
        ariaKeyShortcuts="Meta+Alt+C Control+Alt+C"
        disabled={disabled || !editor}
        icon="codeBlock"
        label="Code block"
        onRun={() => editor?.chain().focus().toggleCodeBlock().run()}
        shortcut="⌘⌥C"
      />

      {isLinkEditorOpen ? (
        <div
          aria-label="Link editor"
          className={styles.linkEditor}
          data-escape-layer="link-editor"
          role="group"
        >
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
          <button
            disabled={!normalizedLink(linkValue)}
            onClick={applyLink}
            type="button"
          >
            Apply
          </button>
        </div>
      ) : null}
    </div>
  );
}

function ToolbarButton({
  active,
  ariaKeyShortcuts,
  disabled,
  icon,
  label,
  onRun,
  shortcut,
}: {
  active: boolean;
  ariaKeyShortcuts: string;
  disabled: boolean;
  icon: IconName;
  label: string;
  onRun: () => void;
  shortcut: string;
}) {
  const tooltipId = useId();

  return (
    <button
      aria-describedby={tooltipId}
      aria-keyshortcuts={ariaKeyShortcuts}
      aria-label={label}
      aria-pressed={active}
      className={`${styles.toolbarButton} ${active ? styles.active : ""}`}
      disabled={disabled}
      onClick={onRun}
      onMouseDown={(event) => event.preventDefault()}
      type="button"
    >
      <Icon name={icon} size={17} />
      <span className={styles.tooltip} id={tooltipId} role="tooltip">
        <span>{label}</span>
        <kbd>{shortcut}</kbd>
      </span>
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

const variantClassNames = {
  dialog: styles.dialog,
  form: styles.form,
  page: styles.page,
};

type FormattingShortcut = "bulletList" | "link" | "orderedList";

const formattingShortcutEvent = "memotrail:formatting-shortcut";

function formattingShortcut(event: KeyboardEvent): FormattingShortcut | null {
  if ((!event.metaKey && !event.ctrlKey) || event.altKey || event.repeat) {
    return null;
  }

  if (!event.shiftKey && event.key.toLocaleLowerCase() === "k") return "link";
  if (event.shiftKey && (event.code === "Digit7" || event.key === "&")) {
    return "orderedList";
  }
  if (event.shiftKey && (event.code === "Digit8" || event.key === "*")) {
    return "bulletList";
  }
  return null;
}
