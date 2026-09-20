import { NextResponse } from "next/server";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { geoapifyConfigured, searchGeoapify } from "@/lib/locations/geoapify";
import { existingLocationFromRow } from "@/lib/locations/location";

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
  const [savedResult, providerResult] = await Promise.allSettled([
    context.client.rpc("search_locations", { p_query: query, p_limit: 7 }),
    configured ? searchGeoapify(query, language) : Promise.resolve([]),
  ]);
  const savedResponse =
    savedResult.status === "fulfilled" ? savedResult.value : null;
  const saved =
    savedResponse && !savedResponse.error && Array.isArray(savedResponse.data)
      ? savedResponse.data
          .map(existingLocationFromRow)
          .filter((location) => location !== null)
      : [];

  return NextResponse.json(
    {
      configured,
      provider:
        providerResult.status === "fulfilled" ? providerResult.value : [],
      providerUnavailable: configured && providerResult.status === "rejected",
      saved,
    },
    { headers: { "Cache-Control": "private, no-store" } },
  );
}
