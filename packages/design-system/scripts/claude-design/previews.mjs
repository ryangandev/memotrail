import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import * as esbuild from "esbuild";
import { cardGroups } from "./catalog.mjs";

// Builds each component's preview card from its specimen file in ./specimens.
//
// A preview is a root element and one classic script. The frame has already loaded the tokens
// CSS, bundle.css, React 18, and bundle.js, so the script reads React and MemoTrail as globals.
// It stays unminified, because the card doubles as an example of how the components are used.

const specimenDirectory = join(
  dirname(fileURLToPath(import.meta.url)),
  "specimens",
);
const target = ["chrome111", "safari16.2", "firefox113"];
const specimenId = /^[a-z][a-z0-9]*(-[a-z0-9]+)+$/;

// Specimen ids start with the component's kebab-case name, as spec ids do, such as badge-tones.
export function specimenPrefix(name) {
  return `${name.replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase()}-`;
}

export function specimenFile(name) {
  const file = join(specimenDirectory, `${name}.jsx`);
  if (!existsSync(file)) {
    throw new Error(
      `${name} has no specimens. Add scripts/claude-design/specimens/${name}.jsx.`,
    );
  }
  return file;
}

const jsxOptions = {
  bundle: true,
  write: false,
  platform: "browser",
  target,
  jsx: "transform",
  jsxFactory: "React.createElement",
  jsxFragment: "React.Fragment",
  logLevel: "silent",
};

// Reads the specimen ids and titles without rendering anything.
export async function readSpecimens(name, iconNames) {
  const result = await esbuild.build({
    ...jsxOptions,
    entryPoints: [specimenFile(name)],
    format: "iife",
    globalName: "specimenModule",
    define: { ICON_NAMES: JSON.stringify(iconNames) },
  });
  const stub = new Proxy({}, { get: () => () => null });
  const context = vm.createContext({
    MemoTrail: stub,
    React: { createElement: () => null, Fragment: "fragment" },
    encodeURIComponent,
  });
  vm.runInContext(result.outputFiles[0].text, context);
  const specimens = context.specimenModule?.specimens;
  if (!specimens || typeof specimens !== "object") {
    throw new Error(`specimens/${name}.jsx must export a specimens object.`);
  }
  return Object.entries(specimens).map(([id, specimen]) => {
    if (!specimenId.test(id) || !id.startsWith(specimenPrefix(name))) {
      throw new Error(
        `specimens/${name}.jsx: the specimen id ${id} must be kebab-case and start with ${specimenPrefix(name)}.`,
      );
    }
    if (
      typeof specimen?.title !== "string" ||
      typeof specimen?.render !== "function"
    ) {
      throw new Error(
        `specimens/${name}.jsx: ${id} needs a title and a render function.`,
      );
    }
    return { id, title: specimen.title };
  });
}

// The spec's specimens choose what the card shows, in its order, with its descriptions. Without a
// spec, the card shows every specimen in the file.
export function specimenOrder(name, available, spec) {
  if (!spec) return available.map(({ id, title }) => ({ id, caption: title }));
  const ids = new Set(available.map(({ id }) => id));
  const listed = new Set(spec.specimens.map(({ id }) => id));
  const missing = spec.specimens
    .filter(({ id }) => !ids.has(id))
    .map(({ id }) => id);
  const unlisted = available
    .filter(({ id }) => !listed.has(id))
    .map(({ id }) => id);
  if (missing.length > 0 || unlisted.length > 0) {
    throw new Error(
      [
        `The ${name} spec and specimens/${name}.jsx list different specimens.`,
        missing.length > 0
          ? `Render these in specimens/${name}.jsx: ${missing.join(", ")}.`
          : null,
        unlisted.length > 0
          ? `List these in the spec, or remove them: ${unlisted.join(", ")}.`
          : null,
      ]
        .filter(Boolean)
        .join(" "),
    );
  }
  return spec.specimens.map(({ id, description }) => ({
    id,
    caption: description,
  }));
}

export async function buildPreview({ component, order, iconNames }) {
  if (!Number.isInteger(component.height) || component.height <= 0) {
    throw new Error(`${component.name} needs a whole-pixel card height.`);
  }
  const result = await esbuild.build({
    ...jsxOptions,
    stdin: {
      contents: [
        `import { specimens } from "./${component.name}.jsx";`,
        `import { mount } from "./runtime.jsx";`,
        `mount(specimens, ${JSON.stringify(order)});`,
      ].join("\n"),
      resolveDir: specimenDirectory,
      sourcefile: `${component.name}.preview.jsx`,
      loader: "jsx",
    },
    format: "iife",
    define: { ICON_NAMES: JSON.stringify(iconNames) },
  });
  return previewDocument(component, result.outputFiles[0].text);
}

// A spec whose component the bundle lacks still gets a card: it names the component, says why it
// is not rendered, and lists the specimens the spec asks for.
export function buildSpecPreview({ spec, group, reason }) {
  const flat = (text) => text.trim().replace(/\s+/g, " ");
  const data = {
    name: spec.name,
    purpose: flat(spec.purpose),
    reason,
    specimens: spec.specimens.map(({ id, description }) => ({
      id,
      description: flat(description),
    })),
  };
  // JSON escapes < so no text can close the script or open a comment.
  const json = JSON.stringify(data, null, 2).replaceAll("<", "\\u003c");
  const script = `(() => {
  const h = React.createElement;
  const data = ${json};
  const text = (role) => ({
    margin: 0,
    fontFamily: "var(--mt-type-" + role + "-font-family)",
    fontSize: "var(--mt-type-" + role + "-font-size)",
    fontWeight: "var(--mt-type-" + role + "-font-weight)",
    lineHeight: "var(--mt-type-" + role + "-line-height)",
  });
  const muted = { color: "var(--mt-color-ink-muted)" };
  ReactDOM.createRoot(document.getElementById("root")).render(
    h(
      "div",
      {
        style: {
          display: "grid",
          gap: "var(--mt-space-3)",
          padding: "var(--mt-space-5)",
          color: "var(--mt-color-ink)",
        },
      },
      h("p", { style: text("card-title") }, data.name),
      h("p", { style: text("body") }, data.purpose),
      h("p", { style: { ...text("caption"), ...muted } }, data.reason),
      h(
        "ul",
        { style: { ...text("caption"), ...muted, margin: 0, paddingLeft: "var(--mt-space-5)" } },
        data.specimens.map((specimen) => h("li", { key: specimen.id }, specimen.description)),
      ),
    ),
  );
})();
`;
  const height = 160 + 24 * spec.specimens.length;
  return previewDocument({ name: spec.name, group, height }, script);
}

function previewDocument(component, script) {
  if (!cardGroups.includes(component.group)) {
    throw new Error(
      `${component.name} has an unknown card group ${component.group}.`,
    );
  }
  for (const forbidden of ["</script", "<!--"]) {
    if (script.toLowerCase().includes(forbidden)) {
      throw new Error(
        `The ${component.name} preview script contains ${forbidden}.`,
      );
    }
  }
  return `<!-- @dsCard group="${component.group}" height=${component.height} -->
<div id="root"></div>
<script>
${script}</script>
`;
}
