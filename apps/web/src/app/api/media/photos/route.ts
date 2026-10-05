import { authenticateAPI, APIError } from "@/lib/auth/api";
import { loadEntryPhotos } from "@/lib/data/entry-photos";
export const runtime = "nodejs";
export async function POST(request: Request) {
  const headers = { "Cache-Control": "private, no-store" };
  try {
    const { client, ownerID } = await authenticateAPI(request);
    const id = new URL(request.url).searchParams.get("entryId");
    if (
      !id ||
      !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(
        id,
      )
    )
      return Response.json(
        { error: "Invalid Entry" },
        { status: 400, headers },
      );
    const entry = await client
      .from("entries")
      .select("id")
      .eq("id", id)
      .eq("owner_id", ownerID)
      .is("deleted_at", null)
      .maybeSingle();
    if (entry.error) throw Error();
    if (!entry.data)
      return Response.json(
        { error: "Entry unavailable" },
        { status: 404, headers },
      );
    const result = await loadEntryPhotos(client, ownerID, id);
    if (!result) throw Error();
    return Response.json(result, { headers });
  } catch (error) {
    return Response.json(
      { error: "Photos unavailable. Try again." },
      { status: error instanceof APIError ? error.status : 503, headers },
    );
  }
}
