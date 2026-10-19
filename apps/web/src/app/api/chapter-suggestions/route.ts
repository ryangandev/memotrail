import { after } from "next/server";
import { cookies } from "next/headers";
import { runChapterSuggestions } from "@/lib/ai/chapter-suggestions";
import {
  aiErrorResponse,
  aiProviderConfigured,
  authenticateAI,
} from "@/lib/ai/server";
import {
  homeTimezoneCookieName,
  localDateInTimezone,
  normalizeHomeTimezone,
} from "@/lib/data/home-input";

export const runtime = "nodejs";
export const maxDuration = 150;

/**
 * Asks whether a Chapter suggestion run is due. The database decides, so this is a cheap
 * no-op unless the person turned Suggest Chapters on and a month has passed. The run
 * happens after the response, and nothing is shown unless it proposes something.
 */
export async function POST(request: Request) {
  try {
    const { client, ownerID } = await authenticateAI(
      request,
      "chapter_suggestion",
    );
    if (aiProviderConfigured()) {
      const timezone = normalizeHomeTimezone(
        (await cookies()).get(homeTimezoneCookieName)?.value,
      );
      const localDate = localDateInTimezone(new Date(), timezone);
      after(() =>
        runChapterSuggestions(client, ownerID, localDate).then(
          () => undefined,
          () => undefined,
        ),
      );
    }
    return new Response(null, {
      status: 202,
      headers: { "Cache-Control": "no-store" },
    });
  } catch (error) {
    return aiErrorResponse(error);
  }
}
