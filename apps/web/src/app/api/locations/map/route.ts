import { getAuthenticatedContext } from "@/lib/data/inbox";
import { locationProviderQuota } from "@/lib/locations/provider-quota";

export async function GET(request: Request) {
  const context = await getAuthenticatedContext();
  if (!context) return new Response(null, { status: 401 });

  const url = new URL(request.url);
  const latitude = Number(url.searchParams.get("lat"));
  const longitude = Number(url.searchParams.get("lon"));
  const card = url.searchParams.get("card") === "1";
  const theme = url.searchParams.get("theme");
  if (theme !== null && theme !== "light" && theme !== "dark")
    return new Response(null, { status: 400 });
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
  if (!apiKey) return coordinatePreview(latitude, longitude, card, theme);
  const quota = await locationProviderQuota(context, "preview");
  if (quota !== "allowed") {
    return new Response(null, { status: quota === "limited" ? 429 : 503 });
  }

  const upstream = new URL("https://maps.geoapify.com/v1/staticmap");
  upstream.searchParams.set(
    "style",
    theme === "dark" ? "dark-matter-brown" : "osm-bright-grey",
  );
  upstream.searchParams.set("width", "720");
  upstream.searchParams.set("height", "280");
  upstream.searchParams.set("scaleFactor", "2");
  upstream.searchParams.set("center", `lonlat:${longitude},${latitude}`);
  upstream.searchParams.set("zoom", "15");
  upstream.searchParams.set(
    "marker",
    `lonlat:${longitude},${latitude};type:material;color:${theme === "dark" ? "#9cb6a5" : "#5c6f5d"};size:48;icon:map-marker-alt;icontype:awesome`,
  );
  upstream.searchParams.set("apiKey", apiKey);

  try {
    const response = await fetch(upstream, {
      cache: "no-store",
      signal: AbortSignal.timeout(8_000),
    });
    if (!response.ok)
      return coordinatePreview(latitude, longitude, card, theme);
    return new Response(await response.arrayBuffer(), {
      headers: {
        "Cache-Control": "private, max-age=3600",
        "Content-Type": response.headers.get("content-type") ?? "image/png",
      },
    });
  } catch {
    return coordinatePreview(latitude, longitude, card, theme);
  }
}

function coordinatePreview(
  latitude: number,
  longitude: number,
  card: boolean,
  theme: string | null,
) {
  const lat = latitude.toFixed(5);
  const lon = longitude.toFixed(5);
  const dark = theme === "dark";
  const background = dark ? "#252824" : "#f3f1eb";
  const grid = dark ? "#3e433f" : "#d9d5ca";
  const labelBackground = dark ? "#343a35" : "#fff";
  const labelColor = dark ? "#e4e7df" : "#4c514b";
  const marker = dark ? "#9cb6a5" : "#5c6f5d";
  const coordinateLabel = card
    ? ""
    : `<rect x="245" y="195" width="230" height="44" rx="22" fill="${labelBackground}"/><text x="360" y="222" text-anchor="middle" font-family="system-ui,sans-serif" font-size="15" fill="${labelColor}">${lat}, ${lon}</text>`;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="720" height="280" viewBox="0 0 720 280"><rect width="720" height="280" fill="${background}"/><path d="M0 68h720M0 140h720M0 212h720M120 0v280M240 0v280M360 0v280M480 0v280M600 0v280" stroke="${grid}" stroke-width="1"/><circle cx="360" cy="126" r="21" fill="${marker}" opacity=".14"/><path d="M360 91a27 27 0 0 0-27 27c0 21 27 52 27 52s27-31 27-52a27 27 0 0 0-27-27Zm0 39a12 12 0 1 1 0-24 12 12 0 0 1 0 24Z" fill="${marker}"/>${coordinateLabel}</svg>`;
  return new Response(svg, {
    headers: {
      "Cache-Control": "private, no-store",
      "Content-Type": "image/svg+xml; charset=utf-8",
    },
  });
}
