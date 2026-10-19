import "server-only";

import type { getAuthenticatedContext } from "@/lib/data/inbox";

type Context = NonNullable<Awaited<ReturnType<typeof getAuthenticatedContext>>>;

export async function locationProviderQuota(
  context: Context,
  kind: "search" | "preview",
): Promise<"allowed" | "limited" | "unavailable"> {
  const { data, error } = await context.client.rpc(
    "consume_location_provider_quota",
    { p_kind: kind },
  );
  if (error) return "unavailable";
  return data === true ? "allowed" : "limited";
}
