import { ChapterSuggestionTrigger } from "@/components/chapter-suggestion-trigger";
import { HomeDashboard } from "@/components/home-dashboard";
import { getHomeWorkspace } from "@/lib/data/home";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  loadReviewNotice,
  loadReviewSettings,
  reviewToday,
} from "@/lib/data/reviews";

export const dynamic = "force-dynamic";

export default async function HomePage() {
  const workspace = await getHomeWorkspace();
  if (!workspace) return null;

  // Both are quiet: a notice only while reviews are on and one is due, and a check that a
  // Chapter suggestion run is due only while Suggest Chapters is on.
  const context = await getAuthenticatedContext();
  const { localDate } = await reviewToday();
  const [settings, reviewNotice] = context
    ? await Promise.all([
        loadReviewSettings(context.client),
        loadReviewNotice(context.client, localDate),
      ])
    : [null, null];
  const firstTimeIds = context
    ? await loadFirstTimeIds(
        context.client,
        workspace.snapshot?.recentEntries.map((entry) => entry.id) ?? [],
      )
    : [];

  return (
    <>
      <HomeDashboard
        firstTimeIds={firstTimeIds}
        reviewNotice={reviewNotice}
        workspace={workspace}
      />
      {settings?.chapterSuggestionsEnabled &&
      settings.pendingSuggestionCount < 3 ? (
        <ChapterSuggestionTrigger />
      ) : null}
    </>
  );
}

/**
 * Which of the recent Entries are First Times, so their rows carry the mark. The Dashboard
 * snapshot does not say, and a row reads fine without the mark if this lookup fails.
 */
async function loadFirstTimeIds(
  client: NonNullable<
    Awaited<ReturnType<typeof getAuthenticatedContext>>
  >["client"],
  entryIds: readonly string[],
) {
  if (entryIds.length === 0) return [];
  const { data, error } = await client
    .from("entries")
    .select("id")
    .in("id", [...entryIds])
    .eq("is_first_time", true)
    .returns<{ id: string }[]>();
  return error ? [] : (data ?? []).map((row) => row.id);
}
