import { authenticateAI, AIError } from "@/lib/ai/server";
import { photoMetadata, MediaError } from "@/lib/media/server";
export const runtime = "nodejs";
export const maxDuration = 60;
export async function POST(request: Request) {
  const headers = { "Cache-Control": "private, no-store" };
  try {
    const { ownerID } = await authenticateAI(request);
    const id = new URL(request.url).searchParams.get("attachmentId");
    if (
      !id ||
      !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(
        id,
      )
    )
      return Response.json(
        { error: "Invalid photo" },
        { status: 400, headers },
      );
    return Response.json(await photoMetadata(ownerID, id), { headers });
  } catch (error) {
    return Response.json(
      { error: "Photo metadata unavailable. The original is unchanged." },
      {
        status:
          error instanceof AIError || error instanceof MediaError
            ? error.status
            : 422,
        headers,
      },
    );
  }
}
