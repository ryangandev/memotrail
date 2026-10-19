import { authenticateAPI, APIError } from "@/lib/auth/api";
import { parseImportAction } from "@/lib/import/contracts";
import { ImportApiError, handleImportAction } from "@/lib/import/jobs";

export const runtime = "nodejs";
// A run works for up to 240 seconds and then asks to be called again.
export const maxDuration = 300;

const maxRequestBytes = 256 * 1024;

async function readJson(request: Request): Promise<unknown> {
  const reader = request.body?.getReader();
  if (!reader)
    throw new ImportApiError(
      "invalid_request",
      400,
      "Choose an import action.",
    );
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      size += next.value.length;
      if (size > maxRequestBytes) {
        await reader.cancel();
        throw new ImportApiError(
          "invalid_request",
          413,
          "The import request is too large.",
        );
      }
      chunks.push(next.value);
    }
  } finally {
    reader.releaseLock();
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw new ImportApiError(
      "invalid_request",
      400,
      "Choose a valid import action.",
    );
  }
}

export async function POST(request: Request) {
  const headers = {
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  };
  try {
    // Shared verified cookie/bearer identity and browser Origin gate. No AI calls.
    const { client, ownerID } = await authenticateAPI(request);
    const action = parseImportAction(await readJson(request));
    if (!action)
      throw new ImportApiError(
        "invalid_request",
        400,
        "Choose a valid import action.",
      );
    const result = await handleImportAction(client, ownerID, action);
    if (result.kind === "csv")
      return new Response(result.body, {
        headers: {
          ...headers,
          "Content-Disposition": `attachment; filename="${result.filename}"`,
          "Content-Type": "text/csv; charset=utf-8",
        },
      });
    return Response.json(result.body, { headers });
  } catch (error) {
    if (error instanceof APIError || error instanceof ImportApiError)
      return Response.json(
        {
          code: error.code,
          error:
            error.status === 401 ? "Sign in again to import." : error.message,
        },
        { headers, status: error.status },
      );
    return Response.json(
      {
        code: "unavailable",
        error: "Import is temporarily unavailable. Your library is unchanged.",
      },
      { headers, status: 503 },
    );
  }
}
