import { ExportSettings } from "@/components/export-settings";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import { storedProfileTimezone } from "@/lib/data/profile-input";
export const dynamic = "force-dynamic";
export default async function ExportPage() {
  const context = await getAuthenticatedContext();
  if (!context) return null;
  const [{ data, error }, profile] = await Promise.all([
    context.client
      .from("export_snapshots")
      .select(
        "id,schema_version,captured_at,expires_at,row_count,json_bytes,datasets",
      )
      .gt("expires_at", new Date().toISOString())
      .order("captured_at", { ascending: false })
      .limit(2),
    context.client
      .from("profiles")
      .select("timezone")
      .eq("user_id", context.userId)
      .single(),
  ]);
  return (
    <ExportSettings
      initial={data ?? []}
      initialError={Boolean(error)}
      timezone={
        storedProfileTimezone(profile.error ? null : profile.data).timezone
      }
    />
  );
}
