import { NextResponse } from "next/server";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { geoapifyConfigured, searchGeoapify } from "@/lib/locations/geoapify";

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
