import { ChapterSuggestionTrigger } from "@/components/chapter-suggestion-trigger";
import { TimelineWorkspace } from "@/components/timeline-workspace";
import { getAuthenticatedContext } from "@/lib/data/inbox";
import {
  loadPendingSuggestion,
  loadReviewSettings,
  reviewToday,
} from "@/lib/data/reviews";
import { getTimelineWorkspace } from "@/lib/data/timeline";

export const dynamic = "force-dynamic";

export default async function TimelinePage() {
  const workspace = await getTimelineWorkspace();

  if (!workspace) {
    return null;
  }

  // Suggestions are silent: a card only when one is waiting, and a quiet check that one is due.
  const context = await getAuthenticatedContext();
  const { localDate } = await reviewToday();
  const [settings, suggestion] = context
    ? await Promise.all([
        loadReviewSettings(context.client),
        loadPendingSuggestion(context.client, localDate),
      ])
    : [null, null];

  return (
    <>
      <TimelineWorkspace
        birthDate={workspace.birthDate}
        birthDateAvailable={workspace.birthDateAvailable}
        chapters={workspace.chapters}
        defaultTimezone={workspace.defaultTimezone}
        firstTimes={workspace.firstTimes}
        loadError={workspace.loadError}
        ownerId={workspace.viewer.id}
        referenceDate={new Date().toISOString()}
        suggestion={suggestion}
        tagOptions={workspace.tagOptions}
      />
      {settings?.chapterSuggestionsEnabled &&
      settings.pendingSuggestionCount < 3 ? (
        <ChapterSuggestionTrigger />
      ) : null}
    </>
  );
}
