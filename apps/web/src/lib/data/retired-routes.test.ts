import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
vi.mock("next/navigation", () => ({
  redirect: vi.fn((to: string) => {
    throw new Error(`redirect:${to}`);
  }),
}));
vi.mock("@/lib/data/inbox", () => ({ getAuthenticatedContext: vi.fn() }));

import { getAuthenticatedContext } from "@/lib/data/inbox";
import { redirectRetiredRecord } from "./retired-routes";

const entry = "10000000-0000-4000-8000-000000000001";

function signedInWith(detail: unknown) {
  const rpc = vi.fn().mockResolvedValue({ data: detail, error: null });
  vi.mocked(getAuthenticatedContext).mockResolvedValue({
    client: { rpc },
  } as unknown as NonNullable<
    Awaited<ReturnType<typeof getAuthenticatedContext>>
  >);
  return rpc;
}

describe("retired record addresses", () => {
  beforeEach(() => vi.resetAllMocks());

  it("opens the Item page of an Entry that still exists", async () => {
    const rpc = signedInWith({ id: entry });
    await expect(redirectRetiredRecord([entry], "/timeline")).rejects.toThrow(
      `redirect:/items/${entry}`,
    );
    expect(rpc).toHaveBeenCalledWith("entry_detail", { p_entry_id: entry });
  });

  it("opens the fallback when the Entry no longer exists", async () => {
    signedInWith(null);
    await expect(redirectRetiredRecord([entry], "/timeline")).rejects.toThrow(
      "redirect:/timeline",
    );
  });

  it("opens the fallback for the list, other paths, and malformed IDs without loading an account", async () => {
    for (const rest of [[], ["bad"], [entry, "edit"]]) {
      await expect(redirectRetiredRecord(rest, "/library")).rejects.toThrow(
        "redirect:/library",
      );
    }
    expect(getAuthenticatedContext).not.toHaveBeenCalled();
  });

  it("opens the fallback when nobody is signed in", async () => {
    vi.mocked(getAuthenticatedContext).mockResolvedValue(null);
    await expect(redirectRetiredRecord([entry], "/timeline")).rejects.toThrow(
      "redirect:/timeline",
    );
  });
});
