export const TRASH_PAGE_SIZE = 25;

export type TrashItemKind =
  "attachment" | "entry" | "habit" | "place" | "person" | "collection";

export type TrashItemInput = {
  deletedAt: string;
  itemId: string;
  itemKind: TrashItemKind;
  revision: number | null;
};

type ParseResult =
  { data: TrashItemInput; success: true } | { message: string; success: false };

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function parseTrashPage(value: string | string[] | undefined) {
  const raw = Array.isArray(value) ? value[0] : value;

  if (!raw) {
    return 1;
  }

  const page = Number(raw);
  return Number.isSafeInteger(page) && page >= 1 && page <= 401 ? page : null;
}

export function trashPageHref(page: number) {
  if (!Number.isSafeInteger(page) || page < 1 || page > 401) {
    return "/trash";
  }

  return page === 1 ? "/trash" : `/trash?page=${page}`;
}

export function parseTrashItemInput(value: unknown): ParseResult {
  if (!isRecord(value)) {
    return invalidItem();
  }

  const { deletedAt, itemId, itemKind, revision } = value;

  if (
    (itemKind !== "attachment" &&
      itemKind !== "entry" &&
      itemKind !== "habit" &&
      itemKind !== "person" &&
      itemKind !== "collection" &&
      itemKind !== "place") ||
    typeof itemId !== "string" ||
    !uuidPattern.test(itemId) ||
    typeof deletedAt !== "string" ||
    deletedAt.length > 64 ||
    !isTimestamp(deletedAt)
  ) {
    return invalidItem();
  }

  if (itemKind === "attachment") {
    if (revision !== null) {
      return invalidItem();
    }
  } else if (
    typeof revision !== "number" ||
    !Number.isSafeInteger(revision) ||
    revision < 1
  ) {
    return invalidItem();
  }

  return {
    data: { deletedAt, itemId, itemKind, revision },
    success: true,
  };
}

function isTimestamp(value: string) {
  return (
    /^\d{4}-\d{2}-\d{2}T/.test(value) && Number.isFinite(Date.parse(value))
  );
}

function invalidItem(): ParseResult {
  return {
    message: "This Trash item is invalid. Refresh and try again.",
    success: false,
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
