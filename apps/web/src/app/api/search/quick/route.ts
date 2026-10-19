import { SEARCH_QUERY_LIMIT } from "@/lib/data/search-input";
import { getQuickSearchResults } from "@/lib/data/search";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const query = new URL(request.url).searchParams.get("q")?.trim() ?? "";
  const headers = { "Cache-Control": "private, no-store" };

  if (query.length > SEARCH_QUERY_LIMIT) {
    return Response.json(
      { error: "Search phrases can be up to 200 characters.", items: [] },
      { headers, status: 400 },
    );
  }

  const result = await getQuickSearchResults(query);
  if (!result) {
    return Response.json(
      { error: "Sign in to search your Entries.", items: [] },
      { headers, status: 401 },
    );
  }

  return Response.json(result, { headers });
}
