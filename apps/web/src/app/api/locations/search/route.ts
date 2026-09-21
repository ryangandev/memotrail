import { NextResponse } from "next/server";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { geoapifyConfigured, searchGeoapify } from "@/lib/locations/geoapify";
import { locationProviderQuota } from "@/lib/locations/provider-quota";

export async function POST(request: Request) {
  const context = await getAuthenticatedContext();
  if (!context) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const url = new URL(request.url);
  const query = url.searchParams.get("query")?.trim() ?? "";
  const language = url.searchParams.get("lang")?.trim() ?? null;
  if (query.length < 2 || query.length > 200) {
    return NextResponse.json({ error: "invalid_query" }, { status: 400 });
  }

  const configured = geoapifyConfigured();
  let provider = [] as Awaited<ReturnType<typeof searchGeoapify>>;
  let providerUnavailable = false;
  if (configured) {
    const quota = await locationProviderQuota(context, "search");
    if (quota !== "allowed") {
      return NextResponse.json(
        {
          error:
            quota === "limited"
              ? "location_rate_limit"
              : "provider_unavailable",
        },
        { status: quota === "limited" ? 429 : 503 },
      );
    }
    try {
      provider = await searchGeoapify(query, language);
    } catch {
      providerUnavailable = true;
    }
  }

  return NextResponse.json(
    {
      configured,
      provider,
      providerUnavailable,
    },
    { headers: { "Cache-Control": "private, no-store" } },
  );
}
