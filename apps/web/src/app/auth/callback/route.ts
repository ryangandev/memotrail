import { NextResponse } from "next/server";
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

function safeRelativePath(value: string | null) {
  if (!value || !value.startsWith("/") || value.includes("\\")) {
    return "/";
  }

  try {
    const trustedBase = new URL("https://memotrail.invalid");
    const target = new URL(value, trustedBase);

    if (target.origin !== trustedBase.origin) {
      return "/";
    }

    return `${target.pathname}${target.search}${target.hash}`;
  } catch {
    return "/";
  }
}

function applicationOrigin(requestUrl: URL) {
  if (process.env.NODE_ENV !== "production") {
    return requestUrl.origin;
  }

  const configuredUrl = process.env.NEXT_PUBLIC_APP_URL?.trim();

  if (!configuredUrl) {
    return requestUrl.origin;
  }

  try {
    return new URL(configuredUrl).origin;
  } catch {
    return requestUrl.origin;
  }
}
