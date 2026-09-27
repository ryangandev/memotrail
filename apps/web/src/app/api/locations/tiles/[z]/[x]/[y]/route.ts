import { getAuthenticatedContext } from "@/lib/data/inbox";
import { locationProviderQuota } from "@/lib/locations/provider-quota";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ z: string; x: string; y: string }> },
) {
  const context = await getAuthenticatedContext();
  if (!context) return new Response(null, { status: 401 });

  const { z: rawZoom, x: rawX, y: rawY } = await params;
  const zoom = Number(rawZoom);
  const x = Number(rawX);
  const y = Number(rawY);
  if (
    ![zoom, x, y].every(Number.isSafeInteger) ||
    zoom < 0 ||
    zoom > 19 ||
    x < 0 ||
    y < 0 ||
    x >= 2 ** zoom ||
    y >= 2 ** zoom
  )
    return new Response(null, { status: 400 });

  const theme = new URL(request.url).searchParams.get("theme");
  if (theme !== null && theme !== "light" && theme !== "dark")
    return new Response(null, { status: 400 });

  const apiKey = process.env.GEOAPIFY_API_KEY?.trim();
  if (!apiKey) return new Response(null, { status: 503 });
  const quota = await locationProviderQuota(context, "tiles");
  if (quota !== "allowed") {
    return new Response(null, { status: quota === "limited" ? 429 : 503 });
  }

  const upstream = new URL(
    `https://maps.geoapify.com/v1/tile/${theme === "dark" ? "dark-matter-brown" : "osm-bright"}/${zoom}/${x}/${y}.png`,
  );
  upstream.searchParams.set("apiKey", apiKey);
  try {
    const response = await fetch(upstream, {
      cache: "no-store",
      signal: AbortSignal.timeout(8_000),
    });
    if (!response.ok) return new Response(null, { status: 502 });
    return new Response(await response.arrayBuffer(), {
      headers: {
        "Cache-Control": "private, max-age=86400",
        "Content-Type": "image/png",
      },
    });
  } catch {
    return new Response(null, { status: 502 });
  }
}
