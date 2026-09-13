import { beforeEach, describe, expect, it, vi } from "vitest";
import { trashEntryPhoto } from "./media-actions";
import { getAuthenticatedContext } from "@/lib/data/inbox";

vi.mock("@/lib/data/inbox", () => ({ getAuthenticatedContext: vi.fn() }));
const entry = "10000000-0000-4000-8000-000000000001";
const photo = "10000000-0000-4000-8000-000000000002";
const owner = "10000000-0000-4000-8000-000000000003";
describe("current Entry photo removal", () => {
  beforeEach(() => vi.resetAllMocks());
  it("rejects malformed identities before loading an account", async () => {
    expect(await trashEntryPhoto("bad", photo)).toBe(false);
    expect(await trashEntryPhoto(entry, "bad")).toBe(false);
    expect(getAuthenticatedContext).not.toHaveBeenCalled();
  });
  it("requires a signed-in owner", async () => {
    vi.mocked(getAuthenticatedContext).mockResolvedValue(null);
    expect(await trashEntryPhoto(entry, photo)).toBe(false);
  });
  it("requires the exact owned active original in the current Entry", async () => {
    const query = {
      select: vi.fn().mockReturnThis(),
      eq: vi.fn().mockReturnThis(),
      is: vi.fn().mockReturnThis(),
      maybeSingle: vi.fn().mockResolvedValue({ data: null, error: null }),
    };
    const rpc = vi.fn();
    vi.mocked(getAuthenticatedContext).mockResolvedValue({
      viewer: { id: owner },
      client: { from: () => query, rpc },
    } as unknown as NonNullable<
      Awaited<ReturnType<typeof getAuthenticatedContext>>
    >);
    expect(await trashEntryPhoto(entry, photo)).toBe(false);
    expect(query.eq.mock.calls).toEqual([
      ["id", photo],
      ["entry_id", entry],
      ["owner_id", owner],
      ["variant", "original"],
    ]);
    expect(query.is).toHaveBeenCalledWith("deleted_at", null);
    expect(rpc).not.toHaveBeenCalled();
    query.maybeSingle.mockResolvedValue({ data: { id: photo }, error: null });
    rpc.mockResolvedValue({ data: [{ attachment_id: photo }], error: null });
    expect(await trashEntryPhoto(entry, photo)).toBe(true);
    expect(rpc).toHaveBeenCalledWith("trash_entry_attachment", {
      p_attachment_id: photo,
    });
    rpc.mockResolvedValue({ data: [], error: null });
    expect(await trashEntryPhoto(entry, photo)).toBe(false);
    rpc.mockResolvedValue({
      data: [{ attachment_id: photo }],
      error: { message: "not confirmed" },
    });
    expect(await trashEntryPhoto(entry, photo)).toBe(false);
  });
});
