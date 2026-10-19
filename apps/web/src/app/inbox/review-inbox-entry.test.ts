import { beforeEach, describe, expect, it, vi } from "vitest";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { reviewInboxEntry } from "./actions";

vi.mock("server-only", () => ({}));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
vi.mock("next/server", () => ({ after: vi.fn() }));
vi.mock("@/lib/data/inbox", () => ({ getAuthenticatedContext: vi.fn() }));
vi.mock("@/lib/ai/suggestions-server", () => ({ suggestForEntry: vi.fn() }));
vi.mock("@/lib/search/search-index", () => ({
  scheduleSearchIndexDrain: vi.fn(),
}));

const entryId = "10000000-0000-4000-8000-000000000001";
const owner = "10000000-0000-4000-8000-000000000003";
const locationId = "10000000-0000-4000-8000-000000000004";

const input = {
  body: "",
  datePrecision: "unknown" as const,
  id: entryId,
  isChapter: true,
  isFirstTime: false,
  location: null,
  occurredAt: null,
  occurredEnd: null,
  occurredLabel: null,
  occurredTimezone: "UTC",
  revision: null,
  tagNames: [],
  title: "Pine Street years",
};

const provider = {
  address: "10 Pine Street",
  city: "Philadelphia",
  confidence: 0.99,
  country: "United States",
  countryCode: "us",
  dataSource: "openstreetmap",
  formattedAddress: "10 Pine Street, Philadelphia, PA",
  kind: "provider" as const,
  latitude: 39.9526,
  longitude: -75.1652,
  matchType: "full_match",
  name: "10 Pine Street",
  postalCode: null,
  provider: "geoapify" as const,
  providerLocationId: "pine-street",
  region: "Pennsylvania",
  resultType: "building",
  timezone: "America/New_York",
};

function signedIn() {
  const single = vi.fn().mockResolvedValue({
    data: { location_id: locationId, locations: { revision: 3 } },
    error: null,
  });
  const query = {
    eq: vi.fn().mockReturnThis(),
    maybeSingle: single,
    select: vi.fn().mockReturnThis(),
  };
  const client = {
    from: vi.fn(() => query),
    rpc: vi.fn().mockResolvedValue({
      data: [{ entry_id: entryId, revision: 1 }],
      error: null,
    }),
  };
  vi.mocked(getAuthenticatedContext).mockResolvedValue({
    client,
    userId: owner,
    viewer: { id: owner },
  } as unknown as NonNullable<
    Awaited<ReturnType<typeof getAuthenticatedContext>>
  >);
  return { client, query };
}

describe("Saving an Entry review", () => {
  beforeEach(() => vi.resetAllMocks());

  it("returns the saved Location a provider choice became, so a retry keeps it", async () => {
    const { client, query } = signedIn();
    expect(await reviewInboxEntry({ ...input, location: provider })).toEqual({
      message: "Changes saved.",
      revision: 1,
      savedLocation: { id: locationId, revision: 3 },
      status: "saved",
    });
    expect(client.from).toHaveBeenCalledWith("entry_locations");
    expect(query.eq.mock.calls).toEqual([
      ["entry_id", entryId],
      ["relationship", "primary"],
    ]);
  });

  it("does not look up a Location when none was chosen", async () => {
    const { client } = signedIn();
    expect(await reviewInboxEntry(input)).toMatchObject({
      savedLocation: null,
      status: "saved",
    });
    expect(client.from).not.toHaveBeenCalled();
  });
});
