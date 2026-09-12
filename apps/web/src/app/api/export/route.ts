import { authenticateAI, AIError } from "@/lib/ai/server";
import {
  ExportError,
  createExportArchive,
  exportDatabaseError,
  getExportSnapshot,
} from "@/lib/export/archive";
import { exportFilename, parseExportAction } from "@/lib/export/contracts";

export const runtime = "nodejs";
export const maxDuration = 300;
export async function POST(request: Request) {
  const headers = {
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  };
  try {
    // Shared verified cookie/bearer identity and browser Origin gate. No AI calls.
    const { client, ownerID } = await authenticateAI(request);
    const reader = request.body?.getReader();
    if (!reader)
      throw new ExportError("invalid_request", 400, "Choose an export action.");
    const chunks: Uint8Array[] = [];
    let size = 0;
    try {
      while (true) {
        const next = await reader.read();
        if (next.done) break;
        size += next.value.length;
        if (size > 512) {
          await reader.cancel();
          throw new ExportError(
            "invalid_request",
            413,
            "The export request is too large.",
          );
        }
        chunks.push(next.value);
      }
    } finally {
      reader.releaseLock();
    }
    let input;
    try {
      input = parseExportAction(
        JSON.parse(Buffer.concat(chunks).toString("utf8")),
      );
    } catch {
      /* Invalid JSON is a client error. */
    }
    if (!input)
      throw new ExportError(
        "invalid_request",
        400,
        "Choose a valid export action and snapshot.",
      );
    if (input.action === "list") {
      const { data, error } = await client
        .from("export_snapshots")
        .select(
          "id,schema_version,captured_at,expires_at,row_count,json_bytes,datasets",
        )
        .gt("expires_at", new Date().toISOString())
        .order("captured_at", { ascending: false })
        .limit(2);
      if (error) exportDatabaseError(error.message);
      return Response.json({ snapshots: data }, { headers });
    }
    if (input.action === "create" || input.action === "discard") {
      const { data, error } =
        input.action === "create"
          ? await client.rpc("create_export_snapshot", {
              p_request_id: input.id,
            })
          : await client.rpc("discard_export_snapshot", {
              p_snapshot_id: input.id,
            });
      if (error) exportDatabaseError(error.message);
      return Response.json(
        input.action === "create" ? { snapshot: data } : { discarded: data },
        { headers },
      );
    }
    const snapshot = await getExportSnapshot(client, input.id!, request.signal);
    return new Response(
      createExportArchive(client, ownerID, snapshot, request.signal),
      {
        headers: {
          ...headers,
          "Content-Type": "application/zip",
          "Content-Disposition": `attachment; filename="${exportFilename(snapshot)}"`,
        },
      },
    );
  } catch (error) {
    if (error instanceof AIError || error instanceof ExportError)
      return Response.json(
        {
          code: error.code,
          error:
            error.status === 401
              ? "Sign in again to export your archive."
              : error.message,
        },
        { status: error.status, headers },
      );
    return Response.json(
      {
        code: "unavailable",
        error: "Export is temporarily unavailable. Your records are unchanged.",
      },
      { status: 503, headers },
    );
  }
}
