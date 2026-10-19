import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

/**
 * Offline evaluation of embedding models for MemoTrail search: how often the right
 * Entry is in the top results for a vague English, Chinese, mixed, or cross-language
 * description, and where the similarity floor should sit. Pure functions here; the CLI
 * in semantic-eval.mjs talks to the model servers.
 */
export const currentModel = JSON.parse(
  readFileSync(
    fileURLToPath(
      new URL("../src/lib/search/semantic-model.json", import.meta.url),
    ),
    "utf8",
  ),
);

export const fixture = JSON.parse(
  readFileSync(
    fileURLToPath(new URL("./semantic-eval-fixture.json", import.meta.url)),
    "utf8",
  ),
);

/**
 * Candidate models. The first is the model MemoTrail ships with, read from
 * semantic-model.json, so the evaluation always includes the current choice.
 * Check each challenger's query format against its model card before trusting a run.
 */
export const candidateProfiles = {
  current: {
    huggingFaceId: currentModel.huggingFaceId,
    queryInstruction: currentModel.queryInstruction,
    queryTemplate: currentModel.queryTemplate,
  },
  harrier: {
    huggingFaceId: "microsoft/harrier-oss-v1-270m",
    queryInstruction: currentModel.queryInstruction,
    queryTemplate: "Instruct: {instruction}\nQuery: {query}",
  },
};

/** Categories where the challenger rule applies: everything that is not plain English. */
export const CHALLENGER_CATEGORIES = ["zh", "cross", "mixed"];
/** Challenger must come within this many recall@5 points of the baseline. */
export const CHALLENGER_TOLERANCE = 0.02;

export function formatQuery(profile, query) {
  return profile.queryTemplate
    .replace("{instruction}", () => profile.queryInstruction)
    .replace("{query}", () => query);
}

export function formatDocument(entry) {
  const title = entry.title?.trim();
  return title ? `${title}\n\n${entry.body}` : entry.body;
}

export function cosine(left, right) {
  let dot = 0;
  let leftEnergy = 0;
  let rightEnergy = 0;
  for (let index = 0; index < left.length; index += 1) {
    dot += left[index] * right[index];
    leftEnergy += left[index] * left[index];
    rightEnergy += right[index] * right[index];
  }
  return dot / (Math.sqrt(leftEnergy * rightEnergy) || 1);
}

export function percentile(sortedValues, fraction) {
  if (sortedValues.length === 0) return null;
  const position = fraction * (sortedValues.length - 1);
  const lower = Math.floor(position);
  const upper = Math.ceil(position);
  return (
    sortedValues[lower] +
    (sortedValues[upper] - sortedValues[lower]) * (position - lower)
  );
}

export function summarize(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const round = (value) =>
    value === null ? null : Math.round(value * 1000) / 1000;
  return {
    count: sorted.length,
    max: round(sorted.at(-1) ?? null),
    median: round(percentile(sorted, 0.5)),
    min: round(sorted[0] ?? null),
    p05: round(percentile(sorted, 0.05)),
    p25: round(percentile(sorted, 0.25)),
    p75: round(percentile(sorted, 0.75)),
    p95: round(percentile(sorted, 0.95)),
  };
}

/** The threshold that best separates relevant from irrelevant pairs (F1), in 0.01 steps. */
export function bestFloor(relevant, irrelevant) {
  let best = { f1: -1, floor: 0.5 };
  for (let step = 5; step <= 95; step += 1) {
    const floor = step / 100;
    const truePositives = relevant.filter((value) => value >= floor).length;
    const falsePositives = irrelevant.filter((value) => value >= floor).length;
    const falseNegatives = relevant.length - truePositives;
    const denominator = 2 * truePositives + falsePositives + falseNegatives;
    const f1 = denominator === 0 ? 0 : (2 * truePositives) / denominator;
    if (f1 > best.f1) best = { f1, floor };
  }
  return { f1: Math.round(best.f1 * 1000) / 1000, floor: best.floor };
}

/**
 * Scores one model. `embed(texts, kind)` returns one vector per text, where `kind` is
 * "query" or "document"; the caller adds any model-specific formatting beforehand.
 */
export async function evaluateModel({ embed, profile, fixtureData = fixture }) {
  const { entries, queries } = fixtureData;
  const documentVectors = await embed(entries.map(formatDocument), "document");
  const queryVectors = await embed(
    queries.map((query) => formatQuery(profile, query.text)),
    "query",
  );

  const relevantSimilarities = [];
  const irrelevantSimilarities = [];
  const strongestNoAnswer = [];
  const perQuery = [];

  queries.forEach((query, queryIndex) => {
    const expected = new Set(query.expected);
    const scored = entries
      .map((entry, entryIndex) => ({
        id: entry.id,
        similarity: cosine(
          queryVectors[queryIndex],
          documentVectors[entryIndex],
        ),
      }))
      .sort((a, b) => b.similarity - a.similarity);

    if (expected.size === 0) {
      strongestNoAnswer.push(scored[0].similarity);
    } else {
      for (const item of scored) {
        (expected.has(item.id)
          ? relevantSimilarities
          : irrelevantSimilarities
        ).push(item.similarity);
      }
    }

    const topFive = scored.slice(0, 5).map((item) => item.id);
    const firstRank = scored.findIndex((item) => expected.has(item.id)) + 1;
    perQuery.push({
      category: query.category,
      hits: expected.size
        ? [...expected].filter((id) => topFive.includes(id)).length
        : 0,
      id: query.id,
      reciprocalRank: expected.size && firstRank > 0 ? 1 / firstRank : 0,
      topId: scored[0].id,
      topSimilarity: scored[0].similarity,
      wanted: expected.size,
    });
  });

  const answerable = perQuery.filter((item) => item.wanted > 0);
  const byCategory = {};
  for (const category of new Set(answerable.map((item) => item.category))) {
    byCategory[category] = recallAndRank(
      answerable.filter((item) => item.category === category),
    );
  }

  const floor = bestFloor(relevantSimilarities, irrelevantSimilarities);
  const leaking = strongestNoAnswer.filter(
    (value) => value >= floor.floor,
  ).length;

  return {
    byCategory,
    floor: {
      ...floor,
      noAnswerQueriesAboveFloor: leaking,
      noAnswerQueries: strongestNoAnswer.length,
    },
    irrelevant: summarize(irrelevantSimilarities),
    noAnswerTopSimilarity: summarize(strongestNoAnswer),
    overall: recallAndRank(answerable),
    perQuery,
    relevant: summarize(relevantSimilarities),
  };
}

function recallAndRank(items) {
  const wanted = items.reduce((sum, item) => sum + item.wanted, 0);
  const hits = items.reduce((sum, item) => sum + item.hits, 0);
  return {
    mrr: round3(
      items.reduce((sum, item) => sum + item.reciprocalRank, 0) /
        (items.length || 1),
    ),
    queries: items.length,
    recallAt5: round3(wanted ? hits / wanted : 0),
  };
}

function round3(value) {
  return Math.round(value * 1000) / 1000;
}

/** Recall@5 over the Chinese, cross-language, and mixed queries together. */
export function nonEnglishRecall(report) {
  const items = report.perQuery.filter(
    (item) => item.wanted > 0 && CHALLENGER_CATEGORIES.includes(item.category),
  );
  return recallAndRank(items).recallAt5;
}

/** The design's rule: keep the baseline unless the challenger is within 2 points. */
export function recommend(baseline, challenger) {
  const baselineRecall = nonEnglishRecall(baseline.report);
  const challengerRecall = nonEnglishRecall(challenger.report);
  const switchModels =
    challengerRecall >= baselineRecall - CHALLENGER_TOLERANCE;
  return {
    baselineRecall,
    challengerRecall,
    choice: switchModels ? challenger.name : baseline.name,
    reason: switchModels
      ? `${challenger.name} is within ${CHALLENGER_TOLERANCE * 100} points of ${baseline.name} on Chinese, mixed, and cross-language recall@5, and is cheaper to run.`
      : `${challenger.name} trails ${baseline.name} by more than ${CHALLENGER_TOLERANCE * 100} points on Chinese, mixed, and cross-language recall@5.`,
  };
}

export function formatReport(results, recommendation) {
  const lines = [];
  for (const { name, report } of results) {
    lines.push(`== ${name} ==`);
    lines.push(
      `overall   recall@5 ${report.overall.recallAt5}  MRR ${report.overall.mrr}  (${report.overall.queries} queries)`,
    );
    for (const [category, scores] of Object.entries(report.byCategory)) {
      lines.push(
        `${category.padEnd(9)} recall@5 ${scores.recallAt5}  MRR ${scores.mrr}  (${scores.queries} queries)`,
      );
    }
    lines.push(`relevant pairs     ${JSON.stringify(report.relevant)}`);
    lines.push(`irrelevant pairs   ${JSON.stringify(report.irrelevant)}`);
    lines.push(
      `no-answer queries  best match ${JSON.stringify(report.noAnswerTopSimilarity)}`,
    );
    lines.push(
      `suggested minSimilarity ${report.floor.floor} (F1 ${report.floor.f1}); ${report.floor.noAnswerQueriesAboveFloor} of ${report.floor.noAnswerQueries} no-answer queries still return something`,
    );
    lines.push("");
  }
  if (recommendation) {
    lines.push(
      `Chinese, mixed, and cross-language recall@5: ${recommendation.baselineRecall} vs ${recommendation.challengerRecall}`,
    );
    lines.push(
      `Recommendation: ${recommendation.choice}. ${recommendation.reason}`,
    );
  }
  return lines.join("\n");
}

/** Embeds texts through an OpenAI-compatible server in small batches. */
export function httpEmbedder({ apiKey, batchSize = 8, model, url }) {
  return async function embed(texts) {
    const vectors = [];
    for (let from = 0; from < texts.length; from += batchSize) {
      const response = await fetch(`${url.replace(/\/+$/, "")}/v1/embeddings`, {
        body: JSON.stringify({
          input: texts.slice(from, from + batchSize),
          model,
        }),
        headers: {
          "Content-Type": "application/json",
          ...(apiKey ? { Authorization: `Bearer ${apiKey}` } : {}),
        },
        method: "POST",
      });
      if (!response.ok) {
        throw new Error(
          `Embedding server answered ${response.status} at ${url}`,
        );
      }
      const payload = await response.json();
      const ordered = [...payload.data].sort((a, b) => a.index - b.index);
      vectors.push(...ordered.map((item) => item.embedding));
    }
    return vectors;
  };
}
