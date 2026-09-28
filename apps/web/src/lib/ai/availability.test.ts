import { expect, it, vi } from "vitest";
vi.mock("server-only", () => ({}));
vi.mock("@supabase/supabase-js", () => ({ createClient: vi.fn() }));
vi.mock("@/lib/supabase/server", () => ({ createClient: vi.fn() }));
import { createClient } from "@supabase/supabase-js";
import { authenticateAI, generateAI } from "./server";
import { saveAISettings } from "@/app/settings/ai/actions";
import { AI_PAUSED_MESSAGE } from "./availability";
import type { AIPreferences } from "./contracts";

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
