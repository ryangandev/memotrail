import { join } from "node:path";
import * as esbuild from "esbuild";
import { componentNames } from "./declarations.mjs";

// Builds the real Web components into one classic script for the Claude Design preview frame.
//
// The frame loads React 18 as window.React and window.ReactDOM, so React is never bundled:
// `react`, `react-dom`, and the automatic JSX runtime resolve to those globals. CSS modules go
// through esbuild's local-css loader into bundle.css, after the app's global base styles. Next.js
// modules are replaced by small shims.

export const bundleNamespace = "MemoTrail";
export const maximumBundleBytes = 6 * 1024 * 1024;

// Chrome 111, Safari 16.2, and Firefox 113 draw color-mix(), which the component CSS uses.
const target = ["chrome111", "safari16.2", "firefox113"];

const globalModules = {
  react: "module.exports = window.React;",
  "react-dom": "module.exports = window.ReactDOM;",
  "react-dom/client": "module.exports = window.ReactDOM;",
  // React 18's UMD build has no jsx-runtime, so the automatic runtime maps onto createElement.
  // jsxs marks children written side by side in JSX, which need no keys, so they are passed as
  // separate arguments; jsx passes its one child, or a mapped list that does need keys, as is.
  "react/jsx-runtime": `const React = window.React;
export const Fragment = React.Fragment;
function config(props, key) {
  const { children, ...rest } = props;
  if (key !== undefined) rest.key = key;
  return [rest, children];
}
export function jsx(type, props, key) {
  const [rest, children] = config(props, key);
  return children === undefined
    ? React.createElement(type, rest)
    : React.createElement(type, rest, children);
}
export function jsxs(type, props, key) {
  const [rest, children] = config(props, key);
  return React.createElement(type, rest, ...children);
}`,
};

const nextShims = {
  "next/link": `import { createElement } from "react";
// Next.js Link is a plain anchor here: the preview has no router to prefetch or navigate with.
export default function Link({ href, prefetch, replace, scroll, shallow, passHref, legacyBehavior, locale, onNavigate, ...props }) {
  return createElement("a", { ...props, href: typeof href === "string" ? href : String(href?.pathname ?? "#") });
}`,
};

export async function buildBundle({ webRoot, components, stylesheet }) {
  const componentDirectory = join(webRoot, "src/components");
  const names = components.flatMap(componentNames);
  const imports = new Map();
  for (const component of components) {
    const list = imports.get(component.source) ?? [];
    list.push(...componentNames(component));
    imports.set(component.source, list);
  }
  const entry = [
    `import "../app/globals.css";`,
    ...[...imports].map(
      ([source, list]) => `import { ${list.join(", ")} } from "./${source}";`,
    ),
    `window.${bundleNamespace} = { ${names.join(", ")} };`,
  ].join("\n");

  const result = await esbuild.build({
    stdin: {
      contents: entry,
      resolveDir: componentDirectory,
      sourcefile: "memotrail-claude-design.tsx",
      loader: "tsx",
    },
    absWorkingDir: webRoot,
    bundle: true,
    write: false,
    outdir: "claude-design",
    entryNames: "bundle",
    format: "iife",
    platform: "browser",
    target,
    minify: true,
    legalComments: "eof",
    charset: "ascii",
    jsx: "automatic",
    tsconfig: join(webRoot, "tsconfig.json"),
    define: { "process.env.NODE_ENV": '"production"' },
    loader: { ".module.css": "local-css", ".css": "css" },
    logLevel: "silent",
    logOverride: { "module-level-directive": "silent" },
    plugins: [shimPlugin()],
  });
  if (result.warnings.length > 0) {
    const messages = await esbuild.formatMessages(result.warnings, {
      kind: "warning",
    });
    throw new Error(
      `esbuild warned while bundling components:\n${messages.join("\n")}`,
    );
  }

  const output = (extension) =>
    result.outputFiles.find((file) => file.path.endsWith(`bundle.${extension}`))
      ?.text;
  const script = output("js");
  const css = output("css");
  if (!script || !css)
    throw new Error("esbuild produced no bundle.js or bundle.css.");
  if (/@font-face/.test(css)) {
    throw new Error(
      "The component CSS now loads a web font. Export its files to project/fonts and list them in tokens.json type.fonts.",
    );
  }

  const header = `/* @ds-bundle: ${JSON.stringify({
    format: 4,
    namespace: bundleNamespace,
    components: names.map((name) => ({ name })),
  })} */`;
  const bundle = `${header}\n${script}`;
  for (const [pattern, label] of [
    [/<\/script/i, "</script"],
    [/<!--/, "<!--"],
  ]) {
    if (pattern.test(bundle)) {
      throw new Error(
        `bundle.js contains ${label}, which would end the preview's script early.`,
      );
    }
  }
  if (Buffer.byteLength(bundle) > maximumBundleBytes) {
    throw new Error(
      `bundle.js is ${Buffer.byteLength(bundle)} bytes; the copy accepts at most ${maximumBundleBytes}.`,
    );
  }

  return { script: bundle, css: `${stylesheet}\n${css}`, names };
}

function shimPlugin() {
  return {
    name: "memotrail-claude-design-shims",
    setup(build) {
      build.onResolve({ filter: /^(react|react-dom)(\/.*)?$/ }, ({ path }) => {
        if (!(path in globalModules)) {
          return {
            errors: [{ text: `${path} has no global in the preview frame.` }],
          };
        }
        return { path, namespace: "memotrail-global" };
      });
      build.onLoad(
        { filter: /.*/, namespace: "memotrail-global" },
        ({ path }) => ({
          contents: globalModules[path],
          loader: "js",
        }),
      );

      build.onResolve({ filter: /^next(\/.*)?$/ }, ({ path, importer }) => {
        if (!(path in nextShims)) {
          return {
            errors: [
              {
                text: `${importer} imports ${path}, which has no Claude Design shim. Add one to nextShims or exclude the component.`,
              },
            ],
          };
        }
        return { path, namespace: "memotrail-next" };
      });
      build.onLoad(
        { filter: /.*/, namespace: "memotrail-next" },
        ({ path }) => ({
          contents: nextShims[path],
          loader: "js",
          resolveDir: build.initialOptions.absWorkingDir,
        }),
      );

      // Token variables come from the copy's tokens.css and the :root block of bundle.css.
      build.onResolve({ filter: /generated-tokens\.css$/ }, ({ path }) => ({
        path,
        namespace: "memotrail-empty",
      }));
      build.onLoad({ filter: /.*/, namespace: "memotrail-empty" }, () => ({
        contents: "",
        loader: "css",
      }));
    },
  };
}
