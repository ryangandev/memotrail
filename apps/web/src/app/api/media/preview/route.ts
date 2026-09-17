import { getAuthenticatedContext } from "@/lib/data/inbox";
import { MEDIA_MAX_BYTES } from "@/lib/media/contracts";
import { renderPhoto } from "@/lib/media/render";

export const runtime = "nodejs";
export const maxDuration = 60;

const responseHeaders = {
  "Cache-Control": "private, no-store",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
};

export async function POST(request: Request) {
  const origin = request.headers.get("origin");
  const requestOrigin = new URL(request.url).origin;
  const configuredOrigin = process.env.NEXT_PUBLIC_APP_URL
    ? new URL(process.env.NEXT_PUBLIC_APP_URL).origin
    : requestOrigin;

  if (!origin || (origin !== requestOrigin && origin !== configuredOrigin)) {
    return new Response(null, { status: 403, headers: responseHeaders });
  }

  const context = await getAuthenticatedContext();
  if (!context) {
    return new Response(null, { status: 401, headers: responseHeaders });
  }

  try {
    const formData = await request.formData();
    const photo = formData.get("photo");
    if (!(photo instanceof File) || photo.size < 1 || photo.size > MEDIA_MAX_BYTES) {
      return new Response(null, { status: 400, headers: responseHeaders });
    }
    const rendered = await renderPhoto(new Uint8Array(await photo.arrayBuffer()));
    const preview = rendered.find((variant) => variant.variant === "thumbnail");
    if (!preview) throw new Error("Preview unavailable");
    return new Response(Uint8Array.from(preview.bytes), {
      headers: { ...responseHeaders, "Content-Type": "image/webp" },
    });
  } catch {
    return new Response(null, { status: 422, headers: responseHeaders });
  }
}
