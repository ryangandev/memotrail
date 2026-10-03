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
