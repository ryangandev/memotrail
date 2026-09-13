import { authenticateAI, AIError } from "@/lib/ai/server";
import { parseMediaPaths } from "@/lib/media/contracts";
import { displayImageURLs } from "@/lib/media/urls";
export const runtime = "nodejs";
export async function POST(request: Request) {
  const headers = { "Cache-Control": "no-store" };
  try {
    const { client } = await authenticateAI(request);
    const reader = request.body?.getReader();
    if (!reader)
      return Response.json(
        { error: "Invalid image request" },
        { status: 400, headers },
      );
    const chunks: Uint8Array[] = [];
    let size = 0;
    try {
      while (true) {
        const next = await reader.read();
        if (next.done) break;
        size += next.value.length;
        if (size > 30_000) {
          await reader.cancel();
          return Response.json(
            { error: "Too many images" },
            { status: 413, headers },
          );
        }
        chunks.push(next.value);
      }
    } finally {
      reader.releaseLock();
    }
    let input;
    try {
      input = parseMediaPaths(
        JSON.parse(Buffer.concat(chunks).toString("utf8")),
      );
    } catch {
      /* Invalid JSON. */
    }
    if (!input)
      return Response.json(
        { error: "Invalid image request" },
        { status: 400, headers },
      );
    const urls = await displayImageURLs(client, input.paths, input.trash);
    return Response.json({ urls: Object.fromEntries(urls) }, { headers });
  } catch (error) {
    return Response.json(
      { error: "Sign in again or retry loading photos." },
      { status: error instanceof AIError ? error.status : 503, headers },
    );
  }
}
