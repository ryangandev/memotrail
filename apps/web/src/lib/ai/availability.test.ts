import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
vi.mock("server-only", () => ({}));
vi.mock("@supabase/supabase-js", () => ({ createClient: vi.fn() }));
vi.mock("@/lib/supabase/server", () => ({ createClient: vi.fn() }));
vi.mock("@/lib/supabase/config", () => ({
  requireSupabasePublicConfig: () => ({ url: "http://local.test" }),
}));
const capture = vi.hoisted(() => ({
  after: vi.fn(),
  context: vi.fn(),
  photos: vi.fn(),
  revision: vi.fn(),
}));
vi.mock("next/server", () => ({ after: capture.after }));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
vi.mock("@/lib/data/inbox", () => ({
  getAuthenticatedContext: capture.context,
}));
vi.mock("@/lib/media/writing-revision", () => ({
  writingRevision: capture.revision,
}));
vi.mock("./suggestion-photos", () => ({ suggestionPhotos: capture.photos }));
import { createClient } from "@supabase/supabase-js";
import { authenticateAI, generateAI } from "./server";
import { suggestForEntry } from "./suggestions-server";
import { saveAISettings } from "@/app/settings/ai/actions";
import { finishInboxCapture, syncInboxEntry } from "@/app/inbox/actions";
import { AI_PAUSED_MESSAGE } from "./availability";
import type { AIPreferences } from "./contracts";

const entryID = "f4d2df16-a506-4be6-a63e-b7b18afe3468";
beforeEach(() => {
  vi.clearAllMocks();
  // A configured provider and saved consent must still not start paused work.
  vi.stubEnv("AI_PROVIDER", "anthropic");
  vi.stubEnv("AI_API_KEY", "synthetic-test-key");
  vi.stubEnv("SUPABASE_SECRET_KEY", "synthetic-test-key");
  vi.stubEnv("AI_CHAT_MODEL", "");
});
afterEach(() => {
  vi.unstubAllEnvs();
});

it("blocks direct generation and stale API requests before any provider or budget work", async () => {
  await expect(
    generateAI("owner", "search", "system", "prompt"),
  ).rejects.toMatchObject({ code: "ai_paused", status: 503 });
  await expect(
    authenticateAI(new Request("http://localhost/api/ai/search")),
  ).rejects.toMatchObject({ code: "ai_paused", status: 503 });
  expect(createClient).not.toHaveBeenCalled();
});

it("does not allow a stale settings form to re-enable AI", async () => {
  expect(await saveAISettings({ enabled: true } as AIPreferences)).toEqual({
    error: AI_PAUSED_MESSAGE,
  });
});

it("refuses Entry suggestions before reading settings, preparing photos, or claiming a row", async () => {
  const query = {
    select: () => query,
    eq: () => query,
    is: () => query,
    limit: async () => ({ data: [], error: null }),
    maybeSingle: async () => ({
      data: {
        id: entryID,
        body: "A quiet afternoon.",
        enabled: true,
        classification: true,
        tagging: true,
        photo_analysis: true,
      },
      error: null,
    }),
  };
  const client = { from: vi.fn(() => query), rpc: vi.fn() };
  const filter = { eq: () => filter };
  const admin = {
    from: vi.fn(() => ({ update: () => filter })),
    rpc: vi.fn(async () => ({
      data: { claimed: true, suggestion: { id: "row", started_at: "now" } },
      error: null,
    })),
  };
  vi.mocked(createClient).mockReturnValue(
    admin as unknown as ReturnType<typeof createClient>,
  );
  capture.photos.mockResolvedValue({ images: [], fingerprint: "a".repeat(64) });
  await expect(
    suggestForEntry(client as unknown as SupabaseClient, "owner", entryID, 1),
  ).rejects.toMatchObject({ code: "ai_paused", status: 503 });
  expect(client.from).not.toHaveBeenCalled();
  expect(capture.photos).not.toHaveBeenCalled();
  expect(createClient).not.toHaveBeenCalled();
  expect(admin.rpc).not.toHaveBeenCalled();
  expect(admin.from).not.toHaveBeenCalled();
});

it("saves a capture to Inbox without scheduling paused suggestion work", async () => {
  const insert = vi.fn(async () => ({ error: null }));
  const rpc = vi.fn();
  capture.context.mockResolvedValue({
    client: { from: () => ({ insert }), rpc },
    userId: "owner",
  });
  expect(
    await syncInboxEntry({
      attachments: [],
      body: "A thought worth keeping.",
      id: entryID,
      occurredAt: "2026-09-01T15:00:00.000Z",
      occurredTimezone: "America/Los_Angeles",
      queuedAt: "2026-09-01T15:00:00.000Z",
      title: null,
      version: 2,
    }),
  ).toEqual({ message: "Saved to Inbox.", status: "synced" });
  expect(insert).toHaveBeenCalledOnce();
  expect(capture.context).toHaveBeenCalledOnce();
  expect(capture.revision).not.toHaveBeenCalled();
  expect(rpc).not.toHaveBeenCalled();
  expect(capture.after).not.toHaveBeenCalled();
});

it("finishes a photo capture without reading its revision or scheduling suggestions", async () => {
  capture.context.mockResolvedValue({
    client: { rpc: vi.fn() },
    userId: "owner",
  });
  await finishInboxCapture(entryID);
  expect(capture.context).not.toHaveBeenCalled();
  expect(capture.revision).not.toHaveBeenCalled();
  expect(capture.after).not.toHaveBeenCalled();
});
