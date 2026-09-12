import { AIError, authenticateAI, aiErrorResponse } from "@/lib/ai/server";
import { parseExplorationRequest } from "@/lib/ai/exploration";
import {
  explorationWorkspace,
  saveExploration,
  sendExploration,
} from "@/lib/ai/exploration-server";
export const runtime = "nodejs";
export const maxDuration = 60;
export async function POST(request: Request) {
  try {
    const { client, ownerID } = await authenticateAI(request);
    const reader = request.body?.getReader();
    if (!reader)
      throw new AIError(
        "invalid_request",
        400,
        "An exploration request is required.",
      );
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
      const part = await reader.read();
      if (part.done) break;
      size += part.value.byteLength;
      if (size > 256000) {
        await reader.cancel();
        throw new AIError(
          "invalid_request",
          413,
          "Exploration request is too large.",
        );
      }
      chunks.push(part.value);
    }
    let raw: unknown;
    try {
      raw = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    } catch {
      throw new AIError("invalid_request", 400, "Invalid exploration request.");
    }
    const input = parseExplorationRequest(raw);
    if (!input)
      throw new AIError(
        "invalid_request",
        400,
        "Check the question, selected Entry, and text lengths.",
      );
    const result =
      input.action === "send"
        ? await sendExploration(client, ownerID, input)
        : input.action === "save"
          ? await saveExploration(client, input)
          : await explorationWorkspace(
              client,
              input.entryID,
              input.beforeSequence,
            );
    return Response.json(result, { headers: { "Cache-Control": "no-store" } });
  } catch (error) {
    return aiErrorResponse(error);
  }
}
