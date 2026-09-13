import { verifyMediaGrant } from "@/lib/media/contracts";
import { mediaImage, MediaError } from "@/lib/media/server";
export const runtime = "nodejs";
export const maxDuration = 60;
export async function GET(request: Request) {
  const headers = {
    "Cache-Control": "private, no-store",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
  };
  const url = new URL(request.url);
  const grant = verifyMediaGrant(
    url.searchParams.get("token") ?? "",
    process.env.SUPABASE_SECRET_KEY ?? "",
  );
  if (!grant) return new Response(null, { status: 401, headers });
  const variant = url.searchParams.get("variant") ?? "display";
  if (variant !== "display" && variant !== "thumbnail")
    return new Response(null, { status: 400, headers });
  try {
    const image = await mediaImage(grant, variant);
    return new Response(image, {
      headers: { ...headers, "Content-Type": "image/webp" },
    });
  } catch (error) {
    const reason =
      error instanceof MediaError
        ? `status_${error.status}`
        : error instanceof Error &&
            [
              "Image decoder unavailable",
              "Image processing failed",
              "Invalid image",
              "Image processing timed out",
            ].includes(error.message)
          ? error.message
          : "processing_unavailable";
    if (!(error instanceof MediaError && error.status < 500))
      console.warn("Private photo preview failed", { reason });
    return new Response(null, {
      status: error instanceof MediaError ? error.status : 422,
      headers,
    });
  }
}
