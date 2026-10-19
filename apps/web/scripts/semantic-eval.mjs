#!/usr/bin/env node
import {
  candidateProfiles,
  evaluateModel,
  formatReport,
  httpEmbedder,
  recommend,
} from "./semantic-eval-lib.mjs";

/**
 * Compares embedding models on the synthetic bilingual fixture. Run it by hand against
 * servers you start yourself (see services/embeddings/README.md); it downloads and
 * deploys nothing.
 *
 *   node scripts/semantic-eval.mjs \
 *     --current http://localhost:8081 \
 *     --harrier http://localhost:8082 \
 *     [--key API_KEY] [--json]
 *
 * `--current` is the model named in src/lib/search/semantic-model.json. With both
 * servers it also applies the decision rule: keep the current model unless the
 * challenger is within 2 recall@5 points on Chinese, mixed, and cross-language queries.
 * Put the suggested minSimilarity into semantic-model.json.
 */
const options = parseArguments(process.argv.slice(2));
const names = Object.keys(candidateProfiles).filter(
  (name) => options.urls[name],
);

if (names.length === 0) {
  console.error(
    "Pass at least one server, for example: --current http://localhost:8081 --harrier http://localhost:8082",
  );
  process.exit(2);
}

const results = [];
for (const name of names) {
  const profile = candidateProfiles[name];
  const embed = httpEmbedder({
    apiKey: options.key,
    model: profile.huggingFaceId,
    url: options.urls[name],
  });
  results.push({ name, report: await evaluateModel({ embed, profile }) });
}

const recommendation =
  results.length === 2 && results[0].name === "current"
    ? recommend(results[0], results[1])
    : null;

console.log(
  options.json
    ? JSON.stringify({ recommendation, results }, null, 2)
    : formatReport(results, recommendation),
);

function parseArguments(argv) {
  const parsed = {
    json: false,
    key: process.env.SEMANTIC_EVAL_API_KEY,
    urls: {},
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--json") parsed.json = true;
    else if (argument === "--key") parsed.key = argv[++index];
    else if (
      argument.startsWith("--") &&
      argument.slice(2) in candidateProfiles
    ) {
      parsed.urls[argument.slice(2)] = argv[++index];
    } else {
      console.error(`Unknown argument ${argument}`);
      process.exit(2);
    }
  }
  return parsed;
}
