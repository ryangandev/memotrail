import { authenticateAPI, APIError } from "@/lib/auth/api";
import { displayImageURLs } from "@/lib/media/urls";
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
    const { data, error } = await client
      .from("attachments")
      .select("id,original_filename,object_path")
      .eq("entry_id", id)
      .eq("owner_id", ownerID)
      .eq("variant", "original")
      .eq("bucket_id", "entry-media")
      .is("deleted_at", null)
      .order("created_at")
      .order("id")
      .limit(101);
    if (error) throw Error();
    const rows = (data ?? []).slice(0, 100);
    const urls = await displayImageURLs(
      client,
      rows.map((v) => v.object_path),
    );
    return Response.json(
      {
        photos: rows.map((v) => ({
          id: v.id,
          name: v.original_filename ?? "Photo",
          imageUrl: urls.get(v.object_path) ?? null,
        })),
        hasMore: (data ?? []).length > 100,
      },
      { headers },
    );
  } catch (error) {
    return Response.json(
      { error: "Photos unavailable. Try again." },
      { status: error instanceof APIError ? error.status : 503, headers },
    );
  }
}
