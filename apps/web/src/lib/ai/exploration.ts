export type ExplorationTurn = {
  id: string;
  entry_id: string;
  sequence: number;
  question: string;
  source_revision: number;
  source_snapshot: Record<string, unknown>;
  status: "generating" | "completed" | "failed";
  answer: string | null;
  model: string | null;
  error_code: string | null;
  created_at: string;
  saved_entries: {
    request_id: string;
    entry_id: string | null;
    title: string | null;
    deleted: boolean;
  }[];
};
export type ExplorationWorkspace = {
  source: { id: string; title: string | null; body: string; revision: number };
  turns: ExplorationTurn[];
  total_count: number;
  links: { id: string; title: string; relationship: string }[];
  linksTruncated: boolean;
};
export type ExplorationRequest =
  | { action: "workspace"; entryID: string; beforeSequence?: number }
  | {
      action: "send";
      entryID: string;
      requestID: string;
      question: string;
      sourceRevision: number;
    }
  | {
      action: "save";
      requestID: string;
      turnID: string;
      title: string;
      body: string;
    };
export const explorationID = (v: unknown): v is string =>
  typeof v === "string" &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
export function parseExplorationRequest(
  value: unknown,
): ExplorationRequest | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const v = value as Record<string, unknown>;
  const keys =
    v.action === "workspace"
      ? ["action", "entryID", "beforeSequence"]
      : v.action === "send"
        ? ["action", "entryID", "requestID", "question", "sourceRevision"]
        : ["action", "requestID", "turnID", "title", "body"];
  if (Object.keys(v).some((k) => !keys.includes(k))) return null;
  if (
    v.action === "workspace" &&
    explorationID(v.entryID) &&
    (v.beforeSequence === undefined ||
      (Number.isSafeInteger(v.beforeSequence) &&
        (v.beforeSequence as number) > 0))
  )
    return v as ExplorationRequest;
  if (
    v.action === "send" &&
    explorationID(v.entryID) &&
    explorationID(v.requestID) &&
    Number.isSafeInteger(v.sourceRevision) &&
    (v.sourceRevision as number) > 0 &&
    typeof v.question === "string" &&
    v.question.trim().length > 0 &&
    v.question.trim().length <= 2000
  )
    return { ...v, question: v.question.trim() } as ExplorationRequest;
  if (
    v.action === "save" &&
    explorationID(v.turnID) &&
    explorationID(v.requestID) &&
    typeof v.title === "string" &&
    v.title.trim().length <= 200 &&
    typeof v.body === "string" &&
    v.body.trim().length > 0 &&
    v.body.trim().length <= 50000
  )
    return {
      ...v,
      title: v.title.trim(),
      body: v.body.trim(),
    } as ExplorationRequest;
  return null;
}

// Bound serialized UTF-8, including escaping, without cutting surrogate pairs.
function clip(text: string, bytes: number) {
  const chars = [...text];
  let low = 0,
    high = chars.length;
  while (low < high) {
    const mid = Math.ceil((low + high) / 2);
    if (
      Buffer.byteLength(JSON.stringify(chars.slice(0, mid).join("")), "utf8") <=
      bytes
    )
      low = mid;
    else high = mid - 1;
  }
  return { text: chars.slice(0, low).join(""), truncated: low < chars.length };
}
export function explorationPrompt(
  turn: ExplorationTurn,
  workspace: ExplorationWorkspace,
) {
  const body = clip(String(turn.source_snapshot.body ?? ""), 16000);
  const title = clip(String(turn.source_snapshot.title ?? ""), 1000);
  const previous = workspace.turns.filter(
    (t) => t.sequence < turn.sequence && t.status === "completed",
  );
  const recent = previous.slice(-8).map((t) => ({
    question: clip(t.question, 1500),
    answer: clip(t.answer ?? "", 2500),
  }));
  return JSON.stringify({
    source: {
      title: title.text,
      body: body.text,
      revision: turn.source_revision,
      excerptOnly:
        body.truncated ||
        title.truncated ||
        turn.source_snapshot.body_truncated === true,
    },
    conversationScope:
      "Only this source excerpt and up to eight recent completed turns are supplied, not all your Entries. Earlier conversation may be omitted or excerpted.",
    olderTurnsOmitted: workspace.total_count > recent.length + 1,
    recentTurns: recent,
    question: turn.question,
  });
}
export const explorationAnswerSchema = {
  type: "object",
  additionalProperties: false,
  required: ["answer"],
  properties: {
    answer: {
      type: "string",
      description: "A concise plain-text response, at most 6000 characters.",
    },
  },
};
export function parseExplorationAnswer(text: string): string | null {
  try {
    const value = JSON.parse(text);
    return value &&
      Object.keys(value).length === 1 &&
      typeof value.answer === "string" &&
      value.answer.trim().length > 0 &&
      value.answer.trim().length <= 12000
      ? value.answer.trim()
      : null;
  } catch {
    return null;
  }
}
