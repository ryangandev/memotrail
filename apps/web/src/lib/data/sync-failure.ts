/**
 * How a pending capture treats a MemoTrail request that failed.
 *
 * - `rejected`: MemoTrail understood the request and will never accept it, so
 *   sending it again cannot help.
 * - `session`: the person must sign in again; nothing about the capture is wrong.
 * - `unavailable`: MemoTrail could not be reached or could not finish the
 *   request, so a later attempt can still succeed.
 */
export type SyncFailure = "rejected" | "session" | "unavailable";

/** The parts of a PostgREST failure that classify it, never its message text. */
export type PostgrestFailure = {
  code?: string | null;
  /** The HTTP status; 0 or absent when the request never got a response. */
  status?: number | null;
};

// PostgREST JWT errors: an invalid or expired token, or no signed-in role.
const sessionCodes = new Set(["PGRST301", "PGRST302", "PGRST303"]);

// Postgres SQLSTATE classes that describe the request itself: data exceptions
// (22, such as text Postgres cannot store), integrity constraint violations
// (23), and program limits the content exceeds (54).
const rejectedSqlStateClasses = new Set(["22", "23", "54"]);

/**
 * Classifies a PostgREST failure by its error code and HTTP status. Anything
 * not known to be permanent stays retryable, so an unfamiliar failure keeps
 * the capture waiting rather than asking the person to discard it.
 */
export function classifySyncFailure({
  code,
  status,
}: PostgrestFailure): SyncFailure {
  if (status === 401 || (code && sessionCodes.has(code))) return "session";
  if (!code) return "unavailable";
  // PGRST1xx: PostgREST refused the request as malformed, such as a body that
  // is not valid JSON. Other PGRST groups are connection, schema cache, and
  // server problems a later attempt can outlive.
  if (/^PGRST1\d\d$/.test(code)) return "rejected";
  // A signed-in person's own write that row-level security or privileges deny.
  if (code === "42501") return "rejected";
  if (
    /^[0-9A-Z]{5}$/.test(code) &&
    rejectedSqlStateClasses.has(code.slice(0, 2))
  )
    return "rejected";
  return "unavailable";
}

/**
 * How a capture photo's Storage upload failed.
 *
 * - `exists`: an earlier attempt already stored this original, perhaps before
 *   its response was lost, so registration can continue.
 * - `denied`: Storage refused the signed-in request. It reports an expired
 *   session exactly like a policy denial, so the caller checks the session.
 * - `too_large` and `unsupported_type`: refusals of this file in particular.
 */
export type UploadFailure =
  SyncFailure | "denied" | "exists" | "too_large" | "unsupported_type";

/** The parts of a Storage failure that classify it, never its message text. */
export type StorageFailure = {
  /** The HTTP status; absent when the request never got a response. */
  status?: number | null;
  /** The status Storage reports in its error body, such as "409". */
  statusCode?: string | null;
};

/**
 * Classifies a Storage upload failure by status. Storage answers most errors
 * with HTTP 400 and puts the real status in its body, so that one comes first.
 * Client errors are permanent; a missing response, a timeout, a lock, rate
 * limiting, and server errors stay retryable.
 */
export function classifyUploadFailure({
  status,
  statusCode,
}: StorageFailure): UploadFailure {
  const reported = Number(statusCode);
  const effective =
    Number.isInteger(reported) && reported >= 100 && reported <= 599
      ? reported
      : (status ?? 0);

  if (effective === 409) return "exists";
  if (effective === 401) return "session";
  if (effective === 403) return "denied";
  if (effective === 413) return "too_large";
  if (effective === 415) return "unsupported_type";
  if (
    effective === 408 ||
    effective === 423 ||
    effective === 425 ||
    effective === 429 ||
    effective >= 500
  )
    return "unavailable";
  if (effective >= 400) return "rejected";
  return "unavailable";
}
