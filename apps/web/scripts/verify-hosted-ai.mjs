// Explicitly opted-in production smoke test. Never reads existing users' writing.
import { randomUUID } from "node:crypto";
import { loadEnvFile } from "node:process";
import { fileURLToPath } from "node:url";
import { createClient } from "@supabase/supabase-js";

if (process.env.MEMOTRAIL_VERIFY_HOSTED_AI !== "1") {
  throw new Error(
    "Set MEMOTRAIL_VERIFY_HOSTED_AI=1 to authorize one isolated hosted AI check.",
  );
}
loadEnvFile(fileURLToPath(new URL("../.env.local", import.meta.url)));
const appURL = "https://memotrail.ryangan.me";
const projectURL = "https://kaivkozeyuwzqrckmyqu.supabase.co";
if (
  process.env.NEXT_PUBLIC_SUPABASE_URL !== projectURL ||
  !process.env.SUPABASE_SECRET_KEY ||
  !process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
) {
  throw new Error(
    "Expected MemoTrail project and server/public credentials are required. No credential values are logged.",
  );
}
const boundedFetch = (input, init = {}) =>
  fetch(input, {
    ...init,
    signal: AbortSignal.timeout(30_000),
    redirect: "error",
  });
const options = {
  auth: { persistSession: false, autoRefreshToken: false },
  global: { fetch: boundedFetch },
};
const admin = createClient(
  projectURL,
  process.env.SUPABASE_SECRET_KEY,
  options,
);
const client = createClient(
  projectURL,
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  options,
);
const marker = randomUUID();
const email = `hosted-smoke-${marker}@memotrail.local`;
let ownerID;
let stage = "authentication-denial";
const report = {
  app: appURL,
  fixture: email,
  results: [],
  cleanup: "not-created",
};

async function check(endpoint, token) {
  const response = await boundedFetch(`${appURL}${endpoint}`, {
    method: "POST",
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
  const payload = await response.json().catch(() => ({}));
  // Only public error identifiers, never credentials, private content, or raw errors.
  report.results.push({
    endpoint,
    session: token === "invalid-token" ? "invalid" : "synthetic",
    status: response.status,
    code:
      typeof payload.code === "string" && /^[a-z_]{1,80}$/.test(payload.code)
        ? payload.code
        : null,
  });
  return response.status;
}

try {
  if ((await check("/api/ai/connection", "invalid-token")) !== 401)
    throw new Error("Hosted authentication denial failed.");
  stage = "account-creation";
  report.cleanup = "creation-unconfirmed-inspect-fixture-before-retry";
  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
    app_metadata: { memotrail_acceptance_fixture: marker },
  });
  if (created.error || !created.data.user)
    throw new Error(
      "Could not confirm synthetic account creation; inspect only the reported fixture address before retrying.",
    );
  ownerID = created.data.user.id;
  report.cleanup = "pending";
  stage = "synthetic-session";
  const link = await admin.auth.admin.generateLink({
    type: "magiclink",
    email,
  });
  if (link.error || !link.data.properties)
    throw new Error("Synthetic session link unavailable.");
  const signed = await client.auth.verifyOtp({
    type: "magiclink",
    token_hash: link.data.properties.hashed_token,
  });
  if (signed.error || !signed.data.session)
    throw new Error("Synthetic session unavailable.");
  stage = "test-budget";
  const workspace = await client.rpc("ai_workspace");
  if (workspace.error || !workspace.data?.preferences)
    throw new Error("Hosted AI preferences unavailable.");
  const configured = await client.rpc("save_ai_preferences", {
    p_expected_revision: workspace.data.preferences.revision,
    p_preferences: {
      enabled: true,
      classification: false,
      tagging: false,
      search: false,
      explore: false,
      resurfacing: false,
      photo_analysis: false,
      monthly_budget_micros: 10_000,
    },
  });
  if (configured.error || !configured.data)
    throw new Error("Could not set the isolated one-cent monthly test budget.");
  stage = "hosted-connection";
  const status = await check(
    "/api/ai/connection",
    signed.data.session.access_token,
  );
  stage = "usage-verification";
  const usage = await client.rpc("ai_workspace");
  if (usage.error || !usage.data)
    throw new Error("Hosted usage verification unavailable.");
  report.charged_micros = usage.data.month_charged_micros;
  report.requests = usage.data.recent_usage.map(
    ({ status, charged_micros }) => ({ status, charged_micros }),
  );
  report.passed =
    status === 200 &&
    report.requests.length === 1 &&
    report.requests[0].status === "completed" &&
    Number.isSafeInteger(report.charged_micros) &&
    report.charged_micros >= 0 &&
    report.charged_micros <= 10_000;
  if (!report.passed) process.exitCode = 1;
} catch {
  report.failure = `Failed at ${stage}; inspect only the reported fixture before retrying. No raw SDK errors are logged.`;
  process.exitCode = 1;
} finally {
  if (ownerID) {
    try {
      const found = await admin.auth.admin.getUserById(ownerID);
      if (
        !found.error &&
        found.data.user?.email === email &&
        found.data.user?.app_metadata?.memotrail_acceptance_fixture === marker
      ) {
        const deleted = await admin.auth.admin.deleteUser(ownerID);
        report.cleanup = deleted.error ? "failed" : "removed-synthetic-account";
      } else {
        report.cleanup = "unverified-do-not-delete";
      }
    } catch {
      report.cleanup = "unconfirmed-inspect-fixture-before-retry";
    }
    if (report.cleanup !== "removed-synthetic-account") process.exitCode = 1;
  }
  console.log(JSON.stringify(report, null, 2));
}
