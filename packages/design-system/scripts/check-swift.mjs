import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { resolveSystem } from "./lib/resolve.mjs";
import {
  checkSwiftSources,
  formatFailure,
  swiftSourceRoot,
} from "./lib/swift-guard.mjs";

// Fails when native Swift writes a visual value by hand instead of reading a design token.
// iOS is not built in CI, so pnpm design-system:check runs this over the sources instead.
//
//   node scripts/check-swift.mjs

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repositoryRoot = resolve(packageRoot, "../..");
const tokenDirectory = resolve(packageRoot, "tokens");

try {
  const system = await resolveSystem({
    resolverPath: resolve(tokenDirectory, "soft-ledger.resolver.json"),
    tokenDirectory,
    root: repositoryRoot,
  });
  const { failures, stale } = await checkSwiftSources({
    root: repositoryRoot,
    system,
  });

  for (const failure of failures) console.error(formatFailure(failure));
  for (const allowance of stale) {
    console.error(
      `${swiftSourceRoot}/${allowance.file}: the allowance for ${allowance.rule}${allowance.match ? ` "${allowance.match}"` : ""} matches nothing; remove it from scripts/lib/swift-guard.mjs.`,
    );
  }

  if (failures.length > 0 || stale.length > 0) {
    console.error(
      `\n${failures.length} hardcoded visual value${failures.length === 1 ? "" : "s"} in ${swiftSourceRoot}. Read the token named after each one, or add a token to packages/design-system/tokens and run pnpm design-system:generate.`,
    );
    process.exitCode = 1;
  } else {
    console.log(`Native Swift reads every visual value from design tokens.`);
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
