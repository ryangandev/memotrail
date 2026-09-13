import "server-only";
import { displayImageURLs } from "@/lib/media/urls";

import { getAuthenticatedContext, type Viewer } from "./inbox";
import {
  parseGoalLinkOptions,
  parseGoalRows,
  type GoalAttachment,
  type GoalLinkOption,
  type GoalRecord,
} from "./goal-record";

export type GoalsWorkspace = {
  collectionOptions: string[];
  goals: GoalRecord[];
  inboxCount: number | undefined;
  linkOptions: GoalLinkOption[];
  loadError: string | null;
  tagOptions: string[];
  viewer: Viewer;
};

type NameRow = { name: string };

export async function getGoalsWorkspace(): Promise<GoalsWorkspace | null> {
  const context = await getAuthenticatedContext();
  if (!context) return null;

  const [goals, links, collections, tags, inbox] = await Promise.all([
    context.client.rpc("goals_workspace", { p_limit: 100, p_offset: 0 }),
    context.client
      .from("entries")
      .select("id,title,body,entry_type,updated_at")
      .eq("owner_id", context.userId)
      .is("deleted_at", null)
      .order("updated_at", { ascending: false })
      .limit(200),
    context.client
      .from("collections")
      .select("name")
      .eq("owner_id", context.userId)
      .is("archived_at", null)
      .order("name")
      .returns<NameRow[]>(),
    context.client
      .from("tags")
      .select("name")
      .eq("owner_id", context.userId)
      .order("name")
      .returns<NameRow[]>(),
    context.client
      .from("entries")
      .select("id", { count: "exact", head: true })
      .eq("owner_id", context.userId)
      .eq("inbox_status", "unreviewed")
      .is("deleted_at", null),
  ]);

  const rows = goals.error ? null : parseGoalRows(goals.data);
  if (!rows) {
    return unavailableWorkspace(context.viewer, inbox.count ?? undefined);
  }

  const attachments = rows.flatMap((goal) => goal.attachments);
  const signedUrls = await signedImageUrls(context.client, attachments);
  const linkOptions = links.error
    ? []
    : (parseGoalLinkOptions(links.data) ?? []);

  return {
    collectionOptions: collections.error
      ? []
      : (collections.data ?? []).map((item) => item.name),
    goals: rows.map((goal) => ({
      ...goal,
      attachments: goal.attachments.map((attachment) => ({
        ...attachment,
        imageUrl: signedUrls.get(attachment.objectPath) ?? null,
      })),
    })),
    inboxCount: inbox.error ? undefined : (inbox.count ?? 0),
    linkOptions,
    loadError: null,
    tagOptions: tags.error ? [] : (tags.data ?? []).map((item) => item.name),
    viewer: context.viewer,
  };
}

async function signedImageUrls(
  client: NonNullable<
    Awaited<ReturnType<typeof getAuthenticatedContext>>
  >["client"],
  attachments: GoalAttachment[],
) {
  const paths = [...new Set(attachments.map((item) => item.objectPath))];
  return displayImageURLs(client, paths);
}

function unavailableWorkspace(
  viewer: Viewer,
  inboxCount: number | undefined,
): GoalsWorkspace {
  return {
    collectionOptions: [],
    goals: [],
    inboxCount,
    linkOptions: [],
    loadError: "MemoTrail could not load your Goals. Refresh to try again.",
    tagOptions: [],
    viewer,
  };
}
