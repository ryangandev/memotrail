import { authenticateAI, AIError, aiErrorResponse } from "@/lib/ai/server";
import { searchWithAI } from "@/lib/ai/search-server";
export const runtime = "nodejs";
export const maxDuration = 90;
export async function POST(request: Request) {
  try {
    const { client, ownerID } = await authenticateAI(request);
    const reader = request.body?.getReader();
    if (!reader)
      throw new AIError(
        "invalid_request",
        400,
        "A search question is required.",
      );
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
      const part = await reader.read();
      if (part.done) break;
      size += part.value.byteLength;
      if (size > 16000) {
        await reader.cancel();
        throw new AIError(
          "invalid_request",
          413,
          "Search request is too large.",
        );
      }
      chunks.push(part.value);
    }
    let input: unknown;
    try {
      input = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    } catch {
      throw new AIError("invalid_request", 400, "Invalid search request.");
    }
    return Response.json(await searchWithAI(client, ownerID, input), {
      headers: { "Cache-Control": "no-store" },
    });
  } catch (error) {
    return aiErrorResponse(error);
  }
}
