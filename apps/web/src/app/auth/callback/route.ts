import { NextResponse } from "next/server";
import { applicationOrigin, safeRelativePath } from "@/lib/auth/redirect";
import { getSupabasePublicConfig } from "@/lib/supabase/config";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: Request) {
  const requestUrl = new URL(request.url);
  const code = requestUrl.searchParams.get("code");
  const next = safeRelativePath(requestUrl.searchParams.get("next"));

  if (code && getSupabasePublicConfig()) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);

    if (!error) {
      return NextResponse.redirect(
        new URL(next, applicationOrigin(requestUrl)),
      );
    }
  }

  return NextResponse.redirect(
    new URL("/auth/error", applicationOrigin(requestUrl)),
  );
}
