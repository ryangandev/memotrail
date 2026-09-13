import { describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { writingRevision } from "./writing-revision";

describe("photo-only writing revision reconciliation", () => {
  it("does not look up a new Entry", async () => {
    const rpc = vi.fn();
    expect(
      await writingRevision({ rpc } as unknown as SupabaseClient, null, null),
    ).toBeNull();
    expect(rpc).not.toHaveBeenCalled();
  });
  it("uses only the owner-scoped server proof, not the latest Entry row", async () => {
    const rpc = vi.fn().mockResolvedValue({ data: 4, error: null });
    expect(
      await writingRevision({ rpc } as unknown as SupabaseClient, "entry", 2),
    ).toBe(4);
    expect(rpc).toHaveBeenCalledWith("entry_writing_revision", {
      p_entry_id: "entry",
      p_expected_revision: 2,
    });
  });
  it.each([null, 1, 3.5, "4", NaN])(
    "retains the original guard on invalid proof %s",
    async (data) => {
      const rpc = vi.fn().mockResolvedValue({ data, error: null });
      expect(
        await writingRevision({ rpc } as unknown as SupabaseClient, "entry", 2),
      ).toBe(2);
    },
  );
  it("retains the original guard on network failure", async () => {
    const rpc = vi.fn().mockRejectedValue(new Error("offline"));
    expect(
      await writingRevision({ rpc } as unknown as SupabaseClient, "entry", 2),
    ).toBe(2);
  });
  it("retains the original guard on server error", async () => {
    const rpc = vi
      .fn()
      .mockResolvedValue({ data: 4, error: { message: "unavailable" } });
    expect(
      await writingRevision({ rpc } as unknown as SupabaseClient, "entry", 2),
    ).toBe(2);
  });
});
