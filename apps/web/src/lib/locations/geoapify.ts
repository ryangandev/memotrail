import "server-only";

import type { ProviderLocation } from "./location";

const endpoint = "https://api.geoapify.com/v1/geocode/autocomplete";

export function geoapifyConfigured() {
  return Boolean(process.env.GEOAPIFY_API_KEY?.trim());
}

export async function searchGeoapify(
  query: string,
  language?: string | null,
): Promise<ProviderLocation[]> {
  const apiKey = process.env.GEOAPIFY_API_KEY?.trim();
  if (!apiKey) return [];

  const url = new URL(endpoint);
  url.searchParams.set("text", query);
  url.searchParams.set("format", "json");
  url.searchParams.set("limit", "7");
  url.searchParams.set("apiKey", apiKey);
  if (language && /^[a-z]{2}$/i.test(language)) {
    url.searchParams.set("lang", language.toLocaleLowerCase());
  }

  const response = await fetch(url, {
    cache: "no-store",
    signal: AbortSignal.timeout(8_000),
  });
  if (!response.ok) throw new Error("geoapify_search_failed");
  return parseGeoapifyResponse(await response.json());
}

export function parseGeoapifyResponse(value: unknown): ProviderLocation[] {
  if (!isRecord(value) || !Array.isArray(value.results)) return [];
  return value.results.flatMap((candidate) => {
    if (!isRecord(candidate)) return [];
    const providerLocationId = string(candidate.place_id);
    const formattedAddress = string(candidate.formatted);
    const latitude = number(candidate.lat);
    const longitude = number(candidate.lon);
    if (
      !providerLocationId ||
      !formattedAddress ||
      latitude === null ||
      longitude === null ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180
    ) {
      return [];
    }
    const rank = record(candidate.rank);
    const datasource = record(candidate.datasource);
    const timezone = record(candidate.timezone);
    return [
      {
        kind: "provider" as const,
        provider: "geoapify" as const,
        providerLocationId,
        name: formattedAddress.slice(0, 200),
        formattedAddress: formattedAddress.slice(0, 1000),
        address: optionalString(candidate.address_line1, 500),
        city:
          optionalString(candidate.city, 200) ??
          optionalString(candidate.county, 200),
        region: optionalString(candidate.state, 200),
        postalCode: optionalString(candidate.postcode, 40),
        country: optionalString(candidate.country, 200),
        countryCode:
          optionalString(candidate.country_code, 2)?.toLowerCase() ?? null,
        latitude,
        longitude,
        timezone: optionalString(timezone?.name, 100),
        resultType: optionalString(candidate.result_type, 100),
        confidence: boundedNumber(rank?.confidence, 0, 1),
        matchType: optionalString(rank?.match_type, 100),
        dataSource: optionalString(datasource?.name, 200),
      },
    ];
  });
}

function optionalString(value: unknown, limit: number) {
  const result = string(value);
  return result ? result.slice(0, limit) : null;
}

function string(value: unknown) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function number(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function boundedNumber(value: unknown, minimum: number, maximum: number) {
  const result = number(value);
  return result !== null && result >= minimum && result <= maximum
    ? result
    : null;
}

function record(value: unknown) {
  return isRecord(value) ? value : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
