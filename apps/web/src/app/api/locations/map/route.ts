import { getAuthenticatedContext } from "@/lib/data/inbox";

export async function GET(request: Request) {
  const context = await getAuthenticatedContext();
  if (!context) return new Response(null, { status: 401 });

  const url = new URL(request.url);
  const latitude = Number(url.searchParams.get("lat"));
  const longitude = Number(url.searchParams.get("lon"));
  if (
    !Number.isFinite(latitude) ||
    !Number.isFinite(longitude) ||
    latitude < -90 ||
    latitude > 90 ||
    longitude < -180 ||
    longitude > 180
  ) {
    return new Response(null, { status: 400 });
  }

  const apiKey = process.env.GEOAPIFY_API_KEY?.trim();
  if (!apiKey) return coordinatePreview(latitude, longitude);

  const upstream = new URL("https://maps.geoapify.com/v1/staticmap");
  upstream.searchParams.set("style", "osm-bright-grey");
  upstream.searchParams.set("width", "720");
  upstream.searchParams.set("height", "280");
  upstream.searchParams.set("scaleFactor", "2");
  upstream.searchParams.set("center", `lonlat:${longitude},${latitude}`);
  upstream.searchParams.set("zoom", "15");
  upstream.searchParams.set(
    "marker",
    `lonlat:${longitude},${latitude};type:material;color:#5c6f5d;size:48;icon:map-marker-alt;icontype:awesome`,
  );
  upstream.searchParams.set("apiKey", apiKey);

  try {
    const response = await fetch(upstream, {
      cache: "no-store",
      signal: AbortSignal.timeout(8_000),
    });
    if (!response.ok) return coordinatePreview(latitude, longitude);
    return new Response(await response.arrayBuffer(), {
      headers: {
        "Cache-Control": "private, max-age=3600",
        "Content-Type": response.headers.get("content-type") ?? "image/png",
      },
    });
  } catch {
    return coordinatePreview(latitude, longitude);
  }
}

function coordinatePreview(latitude: number, longitude: number) {
  const lat = latitude.toFixed(5);
  const lon = longitude.toFixed(5);
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="720" height="280" viewBox="0 0 720 280"><rect width="720" height="280" fill="#f3f1eb"/><path d="M0 68h720M0 140h720M0 212h720M120 0v280M240 0v280M360 0v280M480 0v280M600 0v280" stroke="#d9d5ca" stroke-width="1"/><circle cx="360" cy="126" r="21" fill="#5c6f5d" opacity=".14"/><path d="M360 91a27 27 0 0 0-27 27c0 21 27 52 27 52s27-31 27-52a27 27 0 0 0-27-27Zm0 39a12 12 0 1 1 0-24 12 12 0 0 1 0 24Z" fill="#5c6f5d"/><rect x="245" y="195" width="230" height="44" rx="22" fill="#fff"/><text x="360" y="222" text-anchor="middle" font-family="system-ui,sans-serif" font-size="15" fill="#4c514b">${lat}, ${lon}</text></svg>`;
  return new Response(svg, {
    headers: {
      "Cache-Control": "private, no-store",
      "Content-Type": "image/svg+xml; charset=utf-8",
    },
  });
}
