export const entryTitleLimit = 200;
export const entryBodyLimit = 50_000;

export type InboxEntryInput = {
  body: string;
  title: string | null;
};

export type InboxEntryInputResult =
  | { data: InboxEntryInput; success: true }
  | { message: string; success: false };

export function parseInboxEntryInput(
  formData: FormData,
): InboxEntryInputResult {
  return parseInboxEntryValues({
    body: formValue(formData.get("body")),
    title: formValue(formData.get("title")),
  });
}

export function parseInboxEntryValues(values: {
  body: string;
  title: string;
}): InboxEntryInputResult {
  const title = values.title.trim();
  const body = values.body.trim();

  if (!title && !body) {
    return {
      message: "Write a title or a note before saving.",
      success: false,
    };
  }

  if (title.length > entryTitleLimit) {
    return {
      message: `Keep the title under ${entryTitleLimit} characters.`,
      success: false,
    };
  }

  if (body.length > entryBodyLimit) {
    return {
      message: `Keep the note under ${entryBodyLimit.toLocaleString("en-US")} characters.`,
      success: false,
    };
  }

  return {
    data: {
      body,
      title: title || null,
    },
    success: true,
  };
}

function formValue(value: FormDataEntryValue | null) {
  return typeof value === "string" ? value.trim() : "";
}
