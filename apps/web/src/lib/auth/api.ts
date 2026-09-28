import "server-only";
import { createClient as supabaseClient } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import { requireSupabasePublicConfig } from "@/lib/supabase/config";
import { requestOriginAllowed } from "./origin";

export class APIError extends Error {
  constructor(
    public code: string,
    public status: number,
    message: string,
  ) {
    super(message);
  }
}

// Shared cookie/bearer identity for Web and native clients, independent of AI availability.
export async function authenticateAPI(request: Request) {
  const authorization = request.headers.get("authorization");
  const bearer = authorization?.startsWith("Bearer ") === true;
  if (!requestOriginAllowed(request, bearer, process.env.NEXT_PUBLIC_APP_URL))
    throw new APIError(
      "invalid_origin",
      403,
      "This request must come from MemoTrail.",
    );
  const { url, publishableKey } = requireSupabasePublicConfig();
  const client = bearer
    ? supabaseClient(url, publishableKey, {
        auth: { persistSession: false, autoRefreshToken: false },
        global: { headers: { Authorization: authorization! } },
      })
    : await createClient();
  const { data, error } = await client.auth.getUser(
    bearer ? authorization!.slice(7) : undefined,
  );
  if (error || !data.user)
    throw new APIError(
      "authentication_required",
      401,
      "Sign in again to use MemoTrail.",
    );
  return { client, ownerID: data.user.id };
}
