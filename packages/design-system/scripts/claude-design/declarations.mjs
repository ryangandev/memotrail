import { join, resolve } from "node:path";
import ts from "typescript";

// Writes index.d.ts for the bundle and reads each component's props from it.
//
// TypeScript emits declarations for the bundled Web component files exactly as the app's
// tsconfig compiles them. They are merged into one `MemoTrail` namespace, the type that
// `window.MemoTrail` has, with the same shims the bundle uses: `next/link` is a plain anchor, and
// icon names come from icons.json. The merged file is then type checked, so a declaration that no
// longer resolves stops the export, and the README props come from that checked file.

const virtualIndex = "memotrail-index.ts";

const linkShim = `type Link = (
    props: Omit<ComponentPropsWithoutRef<"a">, "href"> & { href: string },
  ) => import("react").JSX.Element;
  const Link: Link;`;

const readableAliases = new Set(["ReactNode", "IconName", "CSSProperties"]);

const elementTags = {
  HTMLAnchorElement: "a",
  HTMLButtonElement: "button",
  HTMLDivElement: "div",
  HTMLElement: "element",
  HTMLImageElement: "img",
  HTMLInputElement: "input",
  HTMLSelectElement: "select",
  HTMLSpanElement: "span",
  HTMLTextAreaElement: "textarea",
};

export function makeDeclarations({
  webRoot,
  packageRoot,
  components,
  iconNames,
}) {
  const componentDirectory = join(webRoot, "src/components");
  const files = [
    ...new Set(components.map((component) => component.source)),
  ].map((source) => join(componentDirectory, source));
  const { program, options } = sourceProgram(webRoot, files);
  const checker = program.getTypeChecker();
  const exported = new Set(components.flatMap(componentNames));

  const reactImports = new Set();
  const declarations = [];
  const declared = new Map();
  let usesLink = false;

  for (const file of files) {
    const source = program.getSourceFile(file);
    const text = emitDeclaration(program, source);
    const emitted = ts.createSourceFile(
      `${file}.d.ts`,
      text,
      ts.ScriptTarget.Latest,
      true,
    );

    for (const statement of emitted.statements) {
      if (ts.isImportDeclaration(statement)) {
        const specifier = statement.moduleSpecifier.text;
        if (specifier === "react") {
          for (const { imported, local } of importedNames(statement)) {
            if (imported !== local) {
              throw new Error(
                `${file} renames the React type ${imported}; import it by name.`,
              );
            }
            reactImports.add(imported);
          }
        } else if (specifier === "next/link") {
          usesLink = true;
        } else if (specifier === "@/generated/design-system") {
          // IconName is declared from icons.json below.
        } else if (isComponentModule(specifier)) {
          // Merged into the same namespace.
        } else if (specifier.startsWith("@/") || specifier.startsWith(".")) {
          for (const { imported, local } of importedNames(statement)) {
            declarations.push(
              inlineType({
                program,
                checker,
                options,
                file,
                specifier,
                imported,
                local,
              }),
            );
            record(declared, local, file);
          }
        } else {
          throw new Error(
            `${file} declares a type from ${specifier}, which index.d.ts cannot reference. Give the prop a type the copy can read.`,
          );
        }
        continue;
      }
      if (ts.isExportDeclaration(statement)) continue;
      if (statement.kind === ts.SyntaxKind.EmptyStatement) continue;

      const name = statementName(statement);
      if (name) record(declared, name, file);
      declarations.push(namespaceMember(statement, emitted, exported));
    }
  }

  for (const name of exported) {
    if (!declared.has(name)) {
      throw new Error(`No bundled component file declares ${name}.`);
    }
  }

  const imports = [
    ...reactImports,
    ...(usesLink ? ["ComponentPropsWithoutRef"] : []),
  ];
  const text = `// MemoTrail Web components, as window.MemoTrail exposes them in bundle.js.
// Generated from apps/web/src/components by packages/design-system/scripts/export-claude-design.mjs.

import type { ${[...new Set(imports)].sort().join(", ")} } from "react";

declare namespace MemoTrail {
  /** Icon names from packages/design-system/icons.json that Web draws. */
  export type IconName =
${iconNames.map((name) => `    | ${JSON.stringify(name)}`).join("\n")};
${usesLink ? `\n  /** Next.js Link is a plain anchor in the bundle. */\n  ${linkShim}\n` : ""}
${declarations.map((declaration) => indent(declaration)).join("\n\n")}
}

declare global {
  interface Window {
    MemoTrail: typeof MemoTrail;
  }
}

export {};
`;

  const props = readProps(text, packageRoot, components);
  const defaults = readDefaults(
    program,
    checker,
    components,
    componentDirectory,
  );
  const documentation = readDocumentation(
    program,
    checker,
    components,
    componentDirectory,
  );
  return { text, props, defaults, documentation };
}

export function componentNames(component) {
  return [component.name, ...(component.parts ?? []).map((part) => part.name)];
}

function sourceProgram(webRoot, files) {
  const configPath = join(webRoot, "tsconfig.json");
  const config = ts.readConfigFile(configPath, ts.sys.readFile);
  if (config.error)
    throw new Error(
      ts.flattenDiagnosticMessageText(config.error.messageText, "\n"),
    );
  const parsed = ts.parseJsonConfigFileContent(config.config, ts.sys, webRoot);
  const options = {
    ...parsed.options,
    declaration: true,
    emitDeclarationOnly: true,
    noEmit: false,
    incremental: false,
    composite: false,
    tsBuildInfoFile: undefined,
    declarationMap: false,
    sourceMap: false,
    outDir: join(webRoot, ".claude-design-declarations"),
    plugins: [],
  };
  return { program: ts.createProgram({ rootNames: files, options }), options };
}

function emitDeclaration(program, source) {
  let text = null;
  const result = program.emit(
    source,
    (name, contents) => {
      if (name.endsWith(".d.ts")) text = contents;
    },
    undefined,
    true,
  );
  if (result.emitSkipped || text === null) {
    throw new Error(
      `TypeScript could not emit declarations for ${source.fileName}.`,
    );
  }
  return text;
}

function importedNames(statement) {
  const bindings = statement.importClause?.namedBindings;
  if (
    statement.importClause?.name ||
    (bindings && !ts.isNamedImports(bindings))
  ) {
    throw new Error(
      `Only named type imports can be merged: ${statement.getText()}`,
    );
  }
  return (bindings?.elements ?? []).map((element) => ({
    imported: (element.propertyName ?? element.name).text,
    local: element.name.text,
  }));
}

function isComponentModule(specifier) {
  return specifier.startsWith("./") || specifier.startsWith("@/components/");
}

function record(declared, name, file) {
  const owner = declared.get(name);
  if (owner && owner !== file) {
    throw new Error(
      `${name} is declared in both ${owner} and ${file}; index.d.ts merges them into one namespace.`,
    );
  }
  declared.set(name, file);
}

function statementName(statement) {
  if (ts.isVariableStatement(statement)) {
    return statement.declarationList.declarations[0].name.getText();
  }
  return statement.name?.getText() ?? null;
}

// Rewrites a top-level declaration as a namespace member. Inside `declare namespace` every
// member is already ambient, so `declare` goes, and only components and types stay exported:
// the bundle exposes no other values.
function namespaceMember(statement, source, exported) {
  const leading = source.text
    .slice(statement.getFullStart(), statement.getStart(source))
    .trim();
  let body = statement.getText(source);
  if (ts.isFunctionDeclaration(statement)) {
    // Destructured parameters only repeat prop names; one named parameter reads better and
    // avoids renamed bindings, which are not valid outside a declaration file.
    const start = statement.getStart(source);
    for (const parameter of [...statement.parameters].reverse()) {
      if (ts.isIdentifier(parameter.name)) continue;
      body =
        body.slice(0, parameter.name.getStart(source) - start) +
        "props" +
        body.slice(parameter.name.getEnd() - start);
    }
  }
  const isValue =
    ts.isFunctionDeclaration(statement) || ts.isVariableStatement(statement);
  const name = statementName(statement);
  body = body.replace(/^export declare /, "export ").replace(/^declare /, "");
  if (isValue && !exported.has(name)) body = body.replace(/^export /, "");
  return leading ? `${leading}\n${body}` : body;
}

// Copies a type alias or interface that a component imports from elsewhere in the app.
function inlineType({
  program,
  checker,
  options,
  file,
  specifier,
  imported,
  local,
}) {
  const resolved = ts.resolveModuleName(
    specifier,
    file,
    options,
    ts.sys,
  ).resolvedModule;
  const module = resolved && program.getSourceFile(resolved.resolvedFileName);
  const symbol =
    module && checker.getSymbolAtLocation(module)?.exports?.get(imported);
  const declaration = symbol?.declarations?.[0];
  if (
    !declaration ||
    !(
      ts.isTypeAliasDeclaration(declaration) ||
      ts.isInterfaceDeclaration(declaration)
    )
  ) {
    throw new Error(
      `${file} imports ${imported} from ${specifier}, which is not a type alias or interface index.d.ts can copy.`,
    );
  }
  const text = declaration.getText(module).replace(/^export /, "");
  return text.replace(
    ts.isTypeAliasDeclaration(declaration) ? /^type \w+/ : /^interface \w+/,
    `${ts.isTypeAliasDeclaration(declaration) ? "type" : "interface"} ${local}`,
  );
}

function indent(text) {
  return text
    .split("\n")
    .map((line) => (line ? `  ${line}` : line))
    .join("\n");
}

// Type checks the merged declarations and lists each component's own props.
function readProps(text, packageRoot, components) {
  const fileName = resolve(packageRoot, virtualIndex);
  const options = {
    strict: true,
    noEmit: true,
    skipLibCheck: true,
    target: ts.ScriptTarget.ES2022,
    module: ts.ModuleKind.ESNext,
    moduleResolution: ts.ModuleResolutionKind.Bundler,
    jsx: ts.JsxEmit.ReactJSX,
    lib: ["lib.es2022.d.ts", "lib.dom.d.ts"],
    types: [],
  };
  const host = ts.createCompilerHost(options);
  const getSourceFile = host.getSourceFile.bind(host);
  host.getSourceFile = (name, ...rest) =>
    resolve(name) === fileName
      ? ts.createSourceFile(name, text, ts.ScriptTarget.Latest, true)
      : getSourceFile(name, ...rest);
  const fileExists = host.fileExists.bind(host);
  host.fileExists = (name) => resolve(name) === fileName || fileExists(name);
  const readFile = host.readFile.bind(host);
  host.readFile = (name) =>
    resolve(name) === fileName ? text : readFile(name);

  const program = ts.createProgram({ rootNames: [fileName], options, host });
  const diagnostics = ts.getPreEmitDiagnostics(program);
  if (diagnostics.length > 0) {
    throw new Error(
      `index.d.ts does not type check:\n${ts.formatDiagnostics(diagnostics, {
        getCanonicalFileName: (name) => name,
        getCurrentDirectory: () => packageRoot,
        getNewLine: () => "\n",
      })}`,
    );
  }

  const checker = program.getTypeChecker();
  const source = program.getSourceFile(fileName);
  const namespace = source.statements.find(
    (statement) =>
      ts.isModuleDeclaration(statement) && statement.name.text === "MemoTrail",
  );
  const members = checker.getSymbolAtLocation(namespace.name).exports;
  const props = new Map();
  for (const name of components.flatMap(componentNames)) {
    const symbol = members.get(name);
    const signature =
      symbol &&
      checker
        .getTypeOfSymbolAtLocation(symbol, namespace)
        .getCallSignatures()[0];
    if (!signature)
      throw new Error(`index.d.ts does not declare the component ${name}.`);
    const parameter = signature.parameters[0];
    const type = parameter
      ? checker.getTypeOfSymbolAtLocation(parameter, namespace)
      : null;
    const own = [];
    const inherited = [];
    for (const property of type ? checker.getPropertiesOfType(type) : []) {
      const declarations = property.declarations ?? [];
      const propertyType = checker.getTypeOfSymbolAtLocation(
        property,
        namespace,
      );
      const local = declarations.filter(
        (declaration) => declaration.getSourceFile() === source,
      );
      if (local.length > 0) {
        own.push({
          name: property.name,
          required: (property.flags & ts.SymbolFlags.Optional) === 0,
          type: propertyTypeText(local, checker, propertyType, namespace),
          description: ts.displayPartsToString(
            property.getDocumentationComment(checker),
          ),
        });
      } else {
        inherited.push({ name: property.name, type: propertyType });
      }
    }
    const onClick = inherited.find((property) => property.name === "onClick");
    const element = onClick
      ? checker.typeToString(onClick.type).match(/<(HTML\w*Element)>/)?.[1]
      : null;
    props.set(name, {
      own,
      inheritsFrom:
        inherited.length > 0 ? (elementTags[element] ?? "element") : null,
    });
  }
  return props;
}

// The type as written, so aliases such as ReactNode and IconName stay readable. A prop declared in
// several union members lists each written type once.
function propertyTypeText(declarations, checker, type, location) {
  const written = [
    ...new Set(
      declarations
        .map((declaration) => declaration.type?.getText())
        .filter((text) => text && text !== "undefined" && text !== "never"),
    ),
  ];
  // A bare local alias, such as a union of sizes, reads better expanded.
  if (
    written.length === 1 &&
    /^[A-Z]\w*$/.test(written[0]) &&
    !readableAliases.has(written[0])
  ) {
    return checker.typeToString(
      checker.getNonNullableType(type),
      undefined,
      ts.TypeFormatFlags.NoTruncation | ts.TypeFormatFlags.InTypeAlias,
    );
  }
  if (written.length > 0) return written.join(" | ");
  return checker.typeToString(
    checker.getNonNullableType(type),
    location,
    ts.TypeFormatFlags.NoTruncation,
  );
}

function componentDeclaration(
  program,
  checker,
  componentDirectory,
  component,
  name,
) {
  const source = program.getSourceFile(
    join(componentDirectory, component.source),
  );
  const symbol = checker.getSymbolAtLocation(source)?.exports?.get(name);
  return { symbol, declaration: symbol?.declarations?.[0], source };
}

// Defaults live in the source's destructuring, which declarations drop.
function readDefaults(program, checker, components, componentDirectory) {
  const defaults = new Map();
  for (const component of components) {
    for (const name of componentNames(component)) {
      const { declaration, source } = componentDeclaration(
        program,
        checker,
        componentDirectory,
        component,
        name,
      );
      const values = {};
      const pattern = declaration?.parameters?.[0]?.name;
      if (pattern && ts.isObjectBindingPattern(pattern)) {
        for (const element of pattern.elements) {
          if (!element.initializer) continue;
          const key = (element.propertyName ?? element.name).getText(source);
          values[key.replace(/^"|"$/g, "")] =
            element.initializer.getText(source);
        }
      }
      defaults.set(name, values);
    }
  }
  return defaults;
}

function readDocumentation(program, checker, components, componentDirectory) {
  const documentation = new Map();
  for (const component of components) {
    for (const name of componentNames(component)) {
      const { symbol } = componentDeclaration(
        program,
        checker,
        componentDirectory,
        component,
        name,
      );
      documentation.set(
        name,
        symbol
          ? ts.displayPartsToString(symbol.getDocumentationComment(checker))
          : "",
      );
    }
  }
  return documentation;
}
