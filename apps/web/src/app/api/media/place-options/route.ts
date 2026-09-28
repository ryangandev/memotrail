import { APIError, authenticateAPI } from "@/lib/auth/api";

// Retained only so older clients receive an explicit response instead of a
// saved-Location catalog. New Location selection uses provider search.
export async function POST(request: Request) {
  try {
    await authenticateAPI(request);
  } catch (error) {
    return Response.json(
      { error: "unauthorized" },
      { status: error instanceof APIError ? error.status : 503 },
    );
  }
  return Response.json(
    { error: "saved_locations_are_not_available" },
    { status: 410, headers: { "Cache-Control": "private, no-store" } },
  );
}
