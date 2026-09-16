import type { ReactNode } from "react";
import {
  entryRichTextFromMetadata,
  isEntryRichText,
  type EntryRichText,
  type RichTextMark,
  type RichTextNode,
} from "@/lib/data/rich-text";
import styles from "./entry-rich-text-content.module.css";

export function EntryRichTextContent({
  body,
  className,
  metadata,
  richText,
}: {
  body: string;
  className?: string;
  metadata?: unknown;
  richText?: EntryRichText | null;
}) {
  const value = isEntryRichText(richText, body)
    ? richText
    : entryRichTextFromMetadata(metadata, body);

  if (!value) {
    return <p className={className}>{body}</p>;
  }

  return (
    <div
      className={`${styles.content}${className ? ` ${className}` : ""}`}
      data-entry-rich-text
    >
      {value.document.content.map((node, index) =>
        renderNode(node, `root:${index}`),
      )}
    </div>
  );
}

function renderNode(node: RichTextNode, key: string): ReactNode {
  const children = node.content?.map((child, index) =>
    renderNode(child, `${key}:${index}`),
  );

  switch (node.type) {
    case "paragraph":
      return <p key={key}>{children}</p>;
    case "blockquote":
      return <blockquote key={key}>{children}</blockquote>;
    case "bulletList":
      return <ul key={key}>{children}</ul>;
    case "orderedList":
      return (
        <ol
          key={key}
          start={
            typeof node.attrs?.start === "number" ? node.attrs.start : undefined
          }
        >
          {children}
        </ol>
      );
    case "listItem":
      return <li key={key}>{children}</li>;
    case "codeBlock":
      return (
        <pre key={key}>
          <code>{node.content?.map((child) => child.text ?? "").join("")}</code>
        </pre>
      );
    case "hardBreak":
      return <br key={key} />;
    case "text":
      return renderText(node.text ?? "", node.marks ?? [], key);
    default:
      return null;
  }
}

function renderText(text: string, marks: RichTextMark[], key: string) {
  return marks.reduce<ReactNode>((content, mark, index) => {
    const markKey = `${key}:mark:${index}`;

    switch (mark.type) {
      case "bold":
        return <strong key={markKey}>{content}</strong>;
      case "italic":
        return <em key={markKey}>{content}</em>;
      case "underline":
        return <u key={markKey}>{content}</u>;
      case "strike":
        return <s key={markKey}>{content}</s>;
      case "code":
        return <code key={markKey}>{content}</code>;
      case "link":
        return (
          <a
            href={String(mark.attrs?.href)}
            key={markKey}
            rel="noopener noreferrer"
            target="_blank"
          >
            {content}
          </a>
        );
      default:
        return content;
    }
  }, text);
}
