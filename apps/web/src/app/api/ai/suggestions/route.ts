import { authenticateAI, AIError, aiErrorResponse } from "@/lib/ai/server";
import { suggestForEntry } from "@/lib/ai/suggestions-server";
export const runtime = "nodejs";
export const maxDuration = 90;
export async function POST(request: Request) {
  try {
    const { client, ownerID } = await authenticateAI(request);
    const text = await request.text();
    if (text.length > 2000)
      throw new AIError("invalid_request", 400, "Invalid suggestion request.");
    let input;
    try {
      input = JSON.parse(text);
    } catch {
      throw new AIError("invalid_request", 400, "Invalid suggestion request.");
    }
    if (
      !input ||
      typeof input.entryID !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        input.entryID,
      ) ||
      !Number.isSafeInteger(input.revision) ||
      input.revision < 1 ||
      (input.retry !== undefined && typeof input.retry !== "boolean")
    )
      throw new AIError("invalid_request", 400, "Invalid suggestion request.");
    return Response.json(
      await suggestForEntry(
        client,
        ownerID,
        input.entryID,
        input.revision,
        input.retry === true,
      ),
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch (error) {
    return aiErrorResponse(error);
  }
}
