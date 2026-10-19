import { expect } from "@playwright/test";
import type { SupabaseClient } from "@supabase/supabase-js";
import { sql } from "./database";

/** Local synthetic accounts only; include uploads that finished before registration. */
export async function cleanupMediaFixture(
  client: SupabaseClient,
  owner: string,
  apiURL: string,
) {
  expect(apiURL).toMatch(/^http:\/\/127\.0\.0\.1:\d+$/);
  expect(owner).toMatch(/^[a-f0-9-]{36}$/);
  const user = await client.auth.admin.getUserById(owner);
  expect(user.data.user?.email).toMatch(/^media-.+@memotrail\.local$/);
  // A canceled browser load can still finish its bounded server worker.
  // The database deletion guard makes this a retry, never an orphan-producing success.
  await expect
    .poll(
      async () => {
        const paths = sql(
          `select name from storage.objects where bucket_id='entry-media' and split_part(name,'/',1)='${owner}'`,
        )
          .trim()
          .split("\n")
          .filter(Boolean);
        if (
          paths.length &&
          (await client.storage.from("entry-media").remove(paths)).error
        )
          return false;
        return (await client.auth.admin.deleteUser(owner)).error === null;
      },
      { timeout: 15_000 },
    )
    .toBe(true);
}
