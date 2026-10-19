import { after } from "next/server";
import { cookies } from "next/headers";
import {
  AIError,
  aiErrorResponse,
  aiProviderConfigured,
  authenticateAI,
} from "@/lib/ai/server";
import { advanceReview, startReview } from "@/lib/ai/review/jobs";
import type { ReviewSubject } from "@/lib/ai/review/period";
import {
  homeTimezoneCookieName,
  localDateInTimezone,
  normalizeHomeTimezone,
} from "@/lib/data/home-input";

export const runtime = "nodejs";
// A step can wait on the model for several minutes after the response has been sent.
export const maxDuration = 300;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function parseSubject(value: unknown): ReviewSubject | null {
  if (typeof value !== "object" || value === null) return null;
  const input = value as Record<string, unknown>;
  if (
    input.scope === "chapter" &&
    typeof input.chapterId === "string" &&
    UUID.test(input.chapterId) &&
    Object.keys(input).length === 2
  )
    return { scope: "chapter", chapterId: input.chapterId.toLowerCase() };
  if (
    input.scope === "year" &&
    Number.isInteger(input.year) &&
    (input.year as number) >= 1900 &&
    (input.year as number) <= 3000 &&
    Object.keys(input).length === 2
  )
    return { scope: "year", year: input.year as number };
  return null;
}

/** Starts a review. Nothing is sent to the provider until the person has asked for this one. */
export async function POST(request: Request) {
  try {
    const { client, ownerID } = await authenticateAI(request, "review");
    const text = await request.text();
    if (text.length > 400)
      throw new AIError("invalid_request", 400, "Invalid review request.");
    let subject: ReviewSubject | null = null;
    try {
      subject = parseSubject(JSON.parse(text));
    } catch {
      /* Invalid JSON is a client error. */
    }
    if (!subject)
      throw new AIError("invalid_request", 400, "Invalid review request.");
    if (!aiProviderConfigured())
      throw new AIError(
        "provider_unavailable",
        503,
        "Reviews aren't available on this server right now. Your Entries are unchanged.",
      );
    const timezone = normalizeHomeTimezone(
      (await cookies()).get(homeTimezoneCookieName)?.value,
    );
    const started = await startReview(
      client,
      ownerID,
      subject,
      localDateInTimezone(new Date(), timezone),
    );
    after(() =>
      advanceReview(client, ownerID, started.reviewId, started.jobStartedAt).catch(
        () => undefined,
      ),
    );
    return Response.json(
      {
        reviewId: started.reviewId,
        status: "generating",
        done: started.done,
        total: started.total,
      },
      { status: 202, headers: { "Cache-Control": "no-store" } },
    );
  } catch (error) {
    return aiErrorResponse(error);
  }
}
