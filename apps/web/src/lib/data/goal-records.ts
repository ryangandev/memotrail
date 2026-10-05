import "server-only";
import { displayImageURLs } from "@/lib/media/urls";

import { getAuthenticatedContext, type Viewer } from "./inbox";
import {
  parseGoalRows,
  type GoalAttachment,
  type GoalRecord,
} from "./goal-record";

export type GoalsWorkspace = {
  goals: GoalRecord[];
  loadError: string | null;
  tagOptions: string[];
  viewer: Viewer;
};

type NameRow = { name: string };

export async function getGoalsWorkspace(
  targetId?: string,
): Promise<GoalsWorkspace | null> {
  const context = await getAuthenticatedContext();
  if (!context) return null;

  const [goals, tags] = await Promise.all([
    context.client.rpc("goals_workspace", { p_limit: 100, p_offset: 0 }),
    context.client
      .from("tags")
      .select("name")
      .eq("owner_id", context.userId)
      .order("name")
      .returns<NameRow[]>(),
  ]);

  const rows = goals.error ? null : parseGoalRows(goals.data);
  if (!rows) {
    return unavailableWorkspace(context.viewer);
  }

  if (targetId && !rows.some((record) => record.id === targetId)) {
    for (let offset = 100; rows.length >= offset; offset += 100) {
      const page = await context.client.rpc("goals_workspace", {
        p_limit: 100,
        p_offset: offset,
      });
      const more = page.error ? null : parseGoalRows(page.data);
      if (!more) return unavailableWorkspace(context.viewer);
      rows.push(...more);
      if (more.length < 100 || more.some((record) => record.id === targetId))
        break;
    }
  }
  const visibleRows = targetId
    ? rows.filter((record) => record.id === targetId)
    : rows;

  const attachments = visibleRows.flatMap((goal) => goal.attachments);
  const signedUrls = await signedImageUrls(context.client, attachments);

  return {
    goals: visibleRows.map((goal) => ({
      ...goal,
      attachments: goal.attachments.map((attachment) => ({
        ...attachment,
        imageUrl: signedUrls.get(attachment.objectPath) ?? null,
      })),
    })),
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

function unavailableWorkspace(viewer: Viewer): GoalsWorkspace {
  return {
    goals: [],
    loadError: "MemoTrail could not load Want to Do. Refresh to try again.",
    tagOptions: [],
    viewer,
  };
}
