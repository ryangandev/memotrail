import { beforeEach, describe, expect, it, vi } from "vitest";
import { revalidatePath } from "next/cache";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { restoreHistoryVersion } from "./actions";

vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
vi.mock("@/lib/data/inbox", () => ({ getAuthenticatedContext: vi.fn() }));

describe("history restore failure", () => {
  beforeEach(() => vi.resetAllMocks());

  it("explains an unsupported server format if the selected snapshot became stale", async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: null,
      error: { message: "history_schema_unsupported" },
    });
    vi.mocked(getAuthenticatedContext).mockResolvedValue({
      client: { rpc },
    } as unknown as NonNullable<
      Awaited<ReturnType<typeof getAuthenticatedContext>>
    >);
    expect(
      await restoreHistoryVersion("94000000-0000-4000-8000-000000000001", 1, 2),
    ).toBe(
      "This version was saved in a format that cannot be restored. You can still review its recorded content.",
    );
    expect(revalidatePath).not.toHaveBeenCalled();
  });
});
