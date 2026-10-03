import { describe, expect, it } from "vitest";
import { classifySyncFailure } from "./sync-failure";

describe("Capture sync failure classification", () => {
  it.each([
    // Text Postgres cannot store, such as a pasted NUL character.
    ["22P05", 400],
    ["22P02", 400],
    ["22001", 400],
    ["22023", 400],
    ["23502", 400],
    ["23505", 409],
    ["23514", 400],
    ["54000", 400],
    // Row-level security denies the signed-in person's own write.
    ["42501", 403],
    // PostgREST refuses a body that is not valid JSON.
    ["PGRST102", 400],
  ])("rejects %s, which no later attempt can change", (code, status) => {
    expect(classifySyncFailure({ code, status })).toBe("rejected");
  });

  it.each([
    ["PGRST301", 401],
    ["PGRST302", 401],
    ["PGRST303", 401],
    // Without a signed-in role, Postgres denies the anonymous role instead.
    ["42501", 401],
  ])("asks the person to sign in again for %s", (code, status) => {
    expect(classifySyncFailure({ code, status })).toBe("session");
  });

  it.each([
    // The request never reached MemoTrail.
    ["", 0],
    [undefined, undefined],
    [null, 0],
    // PostgREST could not reach or prepare the database.
    ["PGRST000", 503],
    ["PGRST001", 503],
    ["PGRST002", 503],
    ["PGRST003", 504],
    // A schema cache that predates a migration catches up.
    ["PGRST204", 400],
    ["PGRST205", 404],
    ["PGRSTX00", 500],
    // Serialization failures, deadlocks, and cancellations succeed on retry.
    ["40001", 409],
    ["40P01", 409],
    ["57014", 500],
    ["08006", 503],
    ["53300", 503],
    ["XX000", 500],
    // Undeployed schema and custom function errors are not the capture's fault.
    ["42883", 404],
    ["42P01", 404],
    ["P0001", 400],
  ])("keeps %s retryable", (code, status) => {
    expect(classifySyncFailure({ code, status })).toBe("unavailable");
  });
});
