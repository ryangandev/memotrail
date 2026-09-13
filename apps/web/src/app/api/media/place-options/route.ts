import { authenticateAI, AIError } from "@/lib/ai/server";
export async function POST(request: Request) {
  const headers = { "Cache-Control": "private, no-store" };
  try {
    const { client, ownerID } = await authenticateAI(request);
    const query = (new URL(request.url).searchParams.get("query") ?? "").trim();
    if (query.length > 200)
      return Response.json(
        { error: "Search is too long" },
        { status: 400, headers },
      );
    let rows = client
      .from("places")
      .select("id,name,revision,latitude,longitude")
      .eq("owner_id", ownerID)
      .is("deleted_at", null)
      .order("name")
      .order("id")
      .limit(101);
    if (query)
      rows = rows.ilike("name", `%${query.replace(/[\\%_]/g, "\\$&")}%`);
    const { data, error } = await rows;
    if (error) throw error;
    return Response.json(
      {
        places: (data ?? []).slice(0, 100),
        hasMore: (data ?? []).length > 100,
      },
      { headers },
    );
  } catch (error) {
    return Response.json(
      { error: "Places unavailable. Try again." },
      { status: error instanceof AIError ? error.status : 503, headers },
    );
  }
}
