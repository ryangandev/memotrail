import { after } from "next/server";
import {
  AIError,
  aiErrorResponse,
  aiProviderConfigured,
  authenticateAI,
} from "@/lib/ai/server";
import { advanceReview } from "@/lib/ai/review/jobs";

export const runtime = "nodejs";
export const maxDuration = 300;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const headers = { "Cache-Control": "no-store" };

async function reviewID(params: Promise<{ id: string }>) {
  const { id } = await params;
  if (!UUID.test(id))
    throw new AIError("invalid_request", 400, "Invalid review request.");
  return id.toLowerCase();
}

/**
 * The page asks how its review is going. This is a POST, not a GET, because the identity check
 * requires the app's own Origin header, which browsers only send on non-GET requests.
 * While a job is running, asking also resumes it between steps, so a page that was closed
 * and reopened picks the job back up without repeating any request that was paid for.
 */
export async function POST(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  try {
    const { client, ownerID } = await authenticateAI(request, "review");
    const id = await reviewID(params);
    const { data, error } = await client.rpc("entry_review_status", {
      p_review_id: id,
    });
    if (error)
      throw new AIError("review_unavailable", 503, "Could not read this review.");
    if (!data) throw new AIError("not_found", 404, "This review no longer exists.");
    if (data.status === "generating" && aiProviderConfigured()) {
      const job = await client
        .from("entry_reviews")
        .select("job_started_at")
        .eq("id", id)
        .maybeSingle();
      const startedAt = job.data?.job_started_at;
      if (typeof startedAt === "string")
        after(() =>
          advanceReview(client, ownerID, id, startedAt).catch(() => undefined),
        );
    }
    return Response.json(data, { headers });
  } catch (error) {
    return aiErrorResponse(error);
  }
}

/** Deletes one saved review. Reviews can also be deleted by turning reviews off. */
export async function DELETE(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  try {
    const { client } = await authenticateAI(request, "review");
    const id = await reviewID(params);
    const { data, error } = await client.rpc("delete_entry_review", {
      p_review_id: id,
    });
    if (error)
      throw new AIError("review_unavailable", 503, "Could not delete this review.");
    return Response.json({ deleted: data === true }, { headers });
  } catch (error) {
    return aiErrorResponse(error);
  }
}
