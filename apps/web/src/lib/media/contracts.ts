import { createHmac, timingSafeEqual } from "node:crypto";

export const MEDIA_PIPELINE = "v1";
export const MEDIA_MAX_BYTES = 50 * 1024 * 1024;
export const MEDIA_MAX_PIXELS = 80_000_000;
export type MediaVariant = "display" | "thumbnail";
export type MediaGrant = {
  owner: string;
  id: string;
  expires: number;
  trash: boolean;
};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function signMediaGrant(value: MediaGrant, secret: string) {
  const payload = Buffer.from(JSON.stringify(value)).toString("base64url");
  const signature = createHmac("sha256", secret)
    .update(`memotrail:media:${payload}`)
    .digest("base64url");
  return `${payload}.${signature}`;
}
export function verifyMediaGrant(
  token: string,
  secret: string,
  now = Date.now(),
): MediaGrant | null {
  if (token.length > 600 || !secret) return null;
  const [payload, signature, extra] = token.split(".");
  if (!payload || !signature || extra) return null;
  const expected = createHmac("sha256", secret)
    .update(`memotrail:media:${payload}`)
    .digest();
  const actual = Buffer.from(signature, "base64url");
  if (actual.length !== expected.length || !timingSafeEqual(actual, expected))
    return null;
  try {
    const value = JSON.parse(
      Buffer.from(payload, "base64url").toString("utf8"),
    );
    if (
      !uuid.test(value.owner) ||
      !uuid.test(value.id) ||
      typeof value.trash !== "boolean" ||
      !Number.isSafeInteger(value.expires) ||
      value.expires <= now ||
      value.expires > now + 3_600_000
    )
      return null;
    return value;
  } catch {
    return null;
  }
}
export function parseMediaPaths(
  value: unknown,
): { paths: string[]; trash: boolean } | null {
  if (!value || typeof value !== "object") return null;
  const v = value as Record<string, unknown>;
  if (
    !Array.isArray(v.paths) ||
    v.paths.length > 100 ||
    (v.trash !== undefined && typeof v.trash !== "boolean")
  )
    return null;
  if (
    !v.paths.every(
      (p) =>
        typeof p === "string" &&
        p.length < 250 &&
        p.split("/").length === 3 &&
        uuid.test(p.split("/")[0]) &&
        uuid.test(p.split("/")[1]) &&
        /^[a-f0-9-]{36}(\.[A-Za-z0-9]{1,10})?$/.test(p.split("/")[2]),
    )
  )
    return null;
  return { paths: [...new Set(v.paths)], trash: v.trash === true };
}
