import { readFile, readdir } from "node:fs/promises";
import { extname, relative, resolve } from "node:path";
import { Ajv2020 } from "ajv/dist/2020.js";
import { parse } from "yaml";
import { isPublic, platforms } from "./resolve.mjs";
import { kebabCase } from "./util.mjs";

// Component specs: one YAML file per component in components/, validated against
// schema/component-spec.schema.json and then against the code and tokens it describes.

// The token type each part property needs, or the group a property names whole.
export const propertyTypes = {
  background: { type: "color" },
  color: { type: "color" },
  border: { type: "color" },
  borderWidth: { type: "dimension" },
  radius: { type: "dimension" },
  paddingInline: { type: "dimension" },
  paddingBlock: { type: "dimension" },
  gap: { type: "dimension" },
  size: { type: "dimension" },
  minHeight: { type: "dimension" },
  type: { type: "typography" },
  fontFamily: { type: "fontFamily" },
  fontSize: { type: "dimension" },
  fontWeight: { type: "fontWeight" },
  lineHeight: { type: "number" },
  opacity: { type: "number" },
  shadow: { type: "shadow" },
  material: { group: "material" },
  offset: { type: "dimension" },
  duration: { type: "duration" },
  easing: { type: "cubicBezier" },
};

// A symbol counts as declared when the file declares it at the start of a line, so a mention in
// a comment or a call does not satisfy the check.
const declarations = {
  ".ts": "^export\\s+(?:async\\s+)?(?:function|const|class|type|interface)\\s+",
  ".tsx":
    "^export\\s+(?:async\\s+)?(?:function|const|class|type|interface)\\s+",
  ".swift":
    "^\\s*(?:(?:public|internal|fileprivate|private)\\s+)?(?:struct|enum|class|protocol|actor|typealias|func|extension)\\s+",
};

/**
 * Reads every components/*.yaml file, validates it, and returns the specs sorted by file name
 * with their props and specimens normalized for the generators.
 */
export async function loadComponentSpecs({
  componentDirectory,
  schemaPath,
  root,
  system,
}) {
  const schema = JSON.parse(await readFile(schemaPath, "utf8"));
  const validate = new Ajv2020({ allErrors: true, strict: true }).compile(
    schema,
  );
  const files = (await readdir(componentDirectory))
    .filter((file) => file.endsWith(".yaml"))
    .sort();
  if (files.length === 0) {
    throw new Error(`${relative(root, componentDirectory)} has no specs.`);
  }

  const specs = [];
  for (const file of files) {
    const label = relative(root, resolve(componentDirectory, file));
    let spec;
    try {
      spec = parse(await readFile(resolve(componentDirectory, file), "utf8"));
    } catch (error) {
      throw new Error(`${label}: ${error.message}`);
    }
    if (!validate(spec)) {
      throw new Error(
        `${label} does not match the component spec schema:\n${schemaErrors(validate.errors).join("\n")}`,
      );
    }
    specs.push(await checkSpec(spec, { file, label, root, system }));
  }

  const names = new Map();
  const specimens = new Map();
  for (const spec of specs) {
    if (names.has(spec.name)) {
      throw new Error(
        `${spec.label} and ${names.get(spec.name)} both name ${spec.name}.`,
      );
    }
    names.set(spec.name, spec.label);
    for (const specimen of spec.specimens) {
      if (specimens.has(specimen.id)) {
        throw new Error(
          `${spec.label}: specimen ${specimen.id} is already used by ${specimens.get(specimen.id)}.`,
        );
      }
      specimens.set(specimen.id, spec.label);
    }
  }
  return specs;
}

function schemaErrors(errors) {
  const messages = errors
    // A failed oneOf repeats each branch's own errors, which say more.
    .filter((error) => error.keyword !== "oneOf" && error.keyword !== "anyOf")
    .map((error) => {
      const at = error.instancePath || "/";
      const detail =
        error.params.additionalProperty ??
        error.params.unevaluatedProperty ??
        error.params.allowedValues?.join(", ") ??
        error.params.propertyName;
      return `  ${at} ${error.message}${detail ? ` (${detail})` : ""}`;
    });
  return [...new Set(messages)];
}

async function checkSpec(spec, { file, label, root, system }) {
  const fail = (message) => {
    throw new Error(`${label}: ${message}`);
  };
  const kebab = kebabCase(spec.name);
  if (file !== `${kebab}.yaml`) fail(`${spec.name} must be in ${kebab}.yaml.`);

  // Platforms
  const implemented = platforms.filter(
    (platform) => spec.platforms[platform].path,
  );
  if (implemented.length === 0) {
    fail("needs an implementation on at least one platform.");
  }
  for (const platform of implemented) {
    const { path, symbols } = spec.platforms[platform];
    const expected = platform === "web" ? [".ts", ".tsx"] : [".swift"];
    if (!expected.includes(extname(path))) {
      fail(`platforms.${platform}.path ${path} is not a ${platform} source.`);
    }
    let source;
    try {
      source = await readFile(resolve(root, path), "utf8");
    } catch {
      fail(`platforms.${platform}.path ${path} does not exist.`);
    }
    for (const symbol of symbols) {
      const declared = new RegExp(
        `${declarations[extname(path)]}${symbol}\\b`,
        "m",
      );
      if (!declared.test(source)) {
        fail(`${path} does not declare ${symbol}.`);
      }
    }
  }

  // Props
  const props = Object.entries(spec.props).map(([name, prop]) => {
    const where = `props.${name}`;
    const propPlatforms = prop.platforms ?? implemented;
    const missing = propPlatforms.filter(
      (platform) => !implemented.includes(platform),
    );
    if (missing.length > 0) {
      fail(
        `${where} lists ${missing.join(" and ")}, which has no implementation.`,
      );
    }
    for (const platform of Object.keys(prop.platformNames ?? {})) {
      if (!propPlatforms.includes(platform)) {
        fail(
          `${where}.platformNames.${platform} names a platform without the prop.`,
        );
      }
    }
    if (prop.values && !prop.values.includes(prop.default)) {
      fail(`${where}.default ${prop.default} is not one of its values.`);
    }
    return {
      name,
      description: prop.description,
      kind: prop.values ? "enum" : "boolean",
      values: prop.values ?? null,
      default: prop.default,
      platforms: platforms.filter((platform) =>
        propPlatforms.includes(platform),
      ),
      names: Object.fromEntries(
        propPlatforms.map((platform) => [
          platform,
          prop.platformNames?.[platform] ?? name,
        ]),
      ),
    };
  });
  const propsByName = new Map(props.map((prop) => [prop.name, prop]));

  // Token rules
  const parts = new Set(Object.keys(spec.anatomy));
  const states = new Set(spec.states);
  const assigned = new Map();
  spec.tokens.forEach((rule, index) => {
    const where = `tokens[${index}]`;
    let rulePlatforms = implemented;
    for (const [key, condition] of Object.entries(rule.when ?? {})) {
      if (key === "state") {
        if (typeof condition !== "string" || condition === "default") {
          fail(`${where}.when.state must name one state other than default.`);
        }
        if (!states.has(condition)) {
          fail(`${where}.when.state ${condition} is not in states.`);
        }
        continue;
      }
      const prop = propsByName.get(key);
      if (!prop) fail(`${where}.when.${key} is not a prop.`);
      if (prop.kind === "boolean") {
        if (typeof condition !== "boolean") {
          fail(`${where}.when.${key} must be true or false.`);
        }
      } else {
        for (const value of [condition].flat()) {
          if (!prop.values.includes(value)) {
            fail(`${where}.when.${key} ${value} is not one of its values.`);
          }
        }
      }
      rulePlatforms = rulePlatforms.filter((platform) =>
        prop.platforms.includes(platform),
      );
    }

    const styled = Object.keys(rule).filter((key) => key !== "when");
    if (styled.length === 0) fail(`${where} styles no part.`);
    for (const part of styled) {
      if (!parts.has(part)) fail(`${where}.${part} is not in anatomy.`);
      for (const [property, value] of Object.entries(rule[part])) {
        const at = `${where}.${part}.${property}`;
        const references =
          typeof value === "string"
            ? Object.fromEntries(
                rulePlatforms.map((platform) => [platform, value]),
              )
            : value;
        for (const [platform, reference] of Object.entries(references)) {
          if (!rulePlatforms.includes(platform)) {
            fail(
              `${at}.${platform} applies to a platform the rule never reaches.`,
            );
          }
          checkReference(reference, propertyTypes[property], {
            at,
            fail,
            platform,
            system,
          });
        }
        const key = `${JSON.stringify(rule.when ?? {})} ${part}.${property}`;
        if (assigned.has(key)) {
          fail(`${at} repeats ${assigned.get(key)} under the same conditions.`);
        }
        assigned.set(key, at);
      }
    }
  });

  const hitTarget = spec.accessibility.minimumHitTarget;
  if (hitTarget !== "notInteractive") {
    const references =
      typeof hitTarget === "string"
        ? Object.fromEntries(
            implemented.map((platform) => [platform, hitTarget]),
          )
        : hitTarget;
    for (const [platform, reference] of Object.entries(references)) {
      if (!implemented.includes(platform)) {
        fail(
          `accessibility.minimumHitTarget.${platform} has no implementation.`,
        );
      }
      checkReference(reference, propertyTypes.minHeight, {
        at: "accessibility.minimumHitTarget",
        fail,
        platform,
        system,
      });
    }
  }

  // Specimens
  const specimens = spec.specimens.map((specimen, index) => {
    const where = `specimens[${index}]`;
    if (!specimen.id.startsWith(`${kebab}-`)) {
      fail(`${where}.id ${specimen.id} must start with ${kebab}-.`);
    }
    const covers = {};
    for (const [name, values] of Object.entries(specimen.covers ?? {})) {
      const prop = propsByName.get(name);
      if (prop?.kind !== "enum") {
        fail(`${where}.covers.${name} is not an enum prop.`);
      }
      if (values !== "all") {
        for (const value of values) {
          if (!prop.values.includes(value)) {
            fail(`${where}.covers.${name} ${value} is not one of its values.`);
          }
        }
      }
      covers[name] = values === "all" ? [...prop.values] : values;
    }
    return { id: specimen.id, description: specimen.description, covers };
  });

  return {
    ...spec,
    file,
    label,
    kebab,
    implemented,
    props,
    specimens,
  };
}

function checkReference(reference, expected, { at, fail, platform, system }) {
  const path = reference.slice(1, -1);
  if (!isPublic(path)) {
    fail(`${at} references the private ${reference}; use a semantic token.`);
  }
  const tokens = system.platforms[platform].light;
  const inGroup = [...tokens.keys()].some((key) => key.startsWith(`${path}.`));
  if (expected.group) {
    if (path.split(".")[0] !== expected.group || path.split(".").length !== 2) {
      fail(
        `${at} must name a ${expected.group} group, such as {${expected.group}.name}.`,
      );
    }
    if (!inGroup)
      fail(`${at} references ${reference}, which ${platform} lacks.`);
    return;
  }
  const token = tokens.get(path);
  if (!token) {
    fail(
      inGroup
        ? `${at} references the group ${reference}; name one of its tokens.`
        : `${at} references ${reference}, which ${platform} lacks.`,
    );
  }
  if (token.type !== expected.type) {
    fail(
      `${at} needs a ${expected.type} token, but ${reference} is a ${token.type}.`,
    );
  }
}
