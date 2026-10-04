import { PageHeader } from "@/components/page-header";
import Link from "next/link";
import { PageFrame } from "@/components/page-frame";
import { TrackSettings } from "@/components/track-settings";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import type { TrackSetting } from "@/lib/data/tracks";
import styles from "@/components/track-settings.module.css";
export const dynamic = "force-dynamic";
export default async function TrackSettingsPage({
  searchParams,
}: {
  searchParams: Promise<{ page?: string }>;
}) {
  const context = await getAuthenticatedContext();
  if (!context) return null;
  const rawPage = Number((await searchParams).page ?? 1);
  const page =
    Number.isSafeInteger(rawPage) && rawPage > 0 && rawPage < 1000000
      ? rawPage
      : 1;
  const result = await context.client.rpc("timeline_track_settings", {
    p_limit: 50,
    p_offset: (page - 1) * 50,
  });
  const tracks = (result.data ?? []) as TrackSetting[];
  const hasMore = (tracks[0]?.total_count ?? 0) > page * 50;
  return (
    <PageFrame className={styles.workspace} variant="standard">
      <PageHeader
        title={<>Timeline tracks</>}
        eyebrow={<>CHOOSE THE CHAPTERS YOU SEE</>}
        description={
          <>
            Create space for each part of your life. Hidden tracks keep every
            moment and can be shown again anytime.
          </>
        }
      />
      {result.error ? (
        <p role="alert">Tracks could not load. Refresh to try again.</p>
      ) : (
        <TrackSettings tracks={tracks} />
      )}
      {page > 1 || hasMore ? (
        <nav className={styles.pagination} aria-label="Track pages">
          {page > 1 && (
            <Link href={`/timeline/tracks?page=${page - 1}`}>
              Previous tracks
            </Link>
          )}
          <span>Page {page}</span>
          {hasMore && (
            <Link href={`/timeline/tracks?page=${page + 1}`}>More tracks</Link>
          )}
        </nav>
      ) : null}
    </PageFrame>
  );
}
