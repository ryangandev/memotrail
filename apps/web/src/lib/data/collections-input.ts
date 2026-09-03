export const COLLECTION_PAGE_SIZE = 25;

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function parseCollectionId(value: unknown) {
  return typeof value === "string" && uuidPattern.test(value) ? value : null;
}

export function parseCollectionPage(value: string | string[] | undefined) {
  const raw = Array.isArray(value) ? value[0] : value;

  if (!raw) {
    return 1;
  }

  const page = Number(raw);
  return Number.isSafeInteger(page) && page >= 1 && page <= 401 ? page : null;
}

export function collectionPageHref(collectionId: string, page: number) {
  const validId = parseCollectionId(collectionId);

  if (!validId || !Number.isSafeInteger(page) || page < 1 || page > 401) {
    return "/collections";
  }

  return page === 1
    ? `/collections/${validId}`
    : `/collections/${validId}?page=${page}`;
}
