import { authenticateAI, generateAI, aiErrorResponse } from "@/lib/ai/server";
export const runtime = "nodejs";
export async function POST(request: Request) {
  try {
    const { ownerID } = await authenticateAI(request);
    const result = await generateAI(
      ownerID,
      "connection",
      "Reply with OK only.",
      "Connection test.",
      16,
    );
    return Response.json(
      {
        message: "Anthropic connection verified. No personal content was sent.",
        model: result.model,
      },
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch (error) {
    return aiErrorResponse(error);
  }
}
