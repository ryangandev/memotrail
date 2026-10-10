import { join, relative, resolve } from "node:path";
import ts from "typescript";

// Writes index.d.ts for the bundle and reads each component's props from it.
//
// TypeScript emits declarations for the bundled Web component files exactly as the app's
// tsconfig compiles them. They are merged into one `MemoTrail` namespace, the type that
// `window.MemoTrail` has, with the same shim the bundle uses: `next/link` is a plain anchor. Types
// the components import from the rest of the app, such as the unions generated from the component
// specs, are copied in with the types they need, so the file stands alone. The merged file is then
// type checked, so a declaration that no longer resolves stops the export, and the README props
// come from that checked file.

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

export function makeDeclarations({ webRoot, packageRoot, components }) {
  const componentDirectory = join(webRoot, "src/components");
  const files = [
    ...new Set(components.map((component) => component.source)),
  ].map((source) => join(componentDirectory, source));
  const { program, options } = sourceProgram(webRoot, files);
  const checker = program.getTypeChecker();
  const exported = new Set(components.flatMap(componentNames));
  const bundledFiles = new Set(files.map((file) => resolve(file)));

  const reactImports = new Set();
  const members = [];
  const declared = new Map();
  const copied = copier({ program, checker, webRoot, declared, reactImports });
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
        } else if (specifier.startsWith("@/") || specifier.startsWith(".")) {
          const module = ts.resolveModuleName(specifier, file, options, ts.sys)
            .resolvedModule?.resolvedFileName;
          // Another bundled file is merged into the same namespace.
          if (module && bundledFiles.has(resolve(module))) continue;
          for (const { imported, local } of importedNames(statement)) {
            copied.add({ file, specifier, module, imported, local });
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
      members.push(
        namespaceMember({ statement, emitted, source, checker, exported }),
      );
    }
  }

  // Values other than the components only remain when a kept type reads one with typeof, as a
  // local list such as pageFrameVariants is no longer needed once its union is written out.
  const kept = new Set(
    members.filter((member) => !member.hidden).map((member) => member.name),
  );
  for (let grown = true; grown;) {
    grown = false;
    for (const member of members) {
      if (!kept.has(member.name)) continue;
      for (const query of member.queries) {
        if (kept.has(query)) continue;
        kept.add(query);
        grown = true;
      }
    }
  }
  const declarations = members
    .filter((member) => kept.has(member.name))
    .map((member) => member.text);

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
${[
  ...copied.declarations,
  ...(usesLink
    ? [`/** Next.js Link is a plain anchor in the bundle. */\n${linkShim}`]
    : []),
  ...declarations,
]
  .map((declaration) => indent(declaration))
  .join("\n\n")}
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
// the bundle exposes no other values, so other values are hidden unless a type reads them. An
// alias that resolves to a union of literals, such as (typeof pageFrameVariants)[number], is
// written out as that union.
function namespaceMember({ statement, emitted, source, checker, exported }) {
  let leading = emitted.text
    .slice(statement.getFullStart(), statement.getStart(emitted))
    .trim();
  const name = statementName(statement);
  const isValue =
    ts.isFunctionDeclaration(statement) || ts.isVariableStatement(statement);
  let body = statement.getText(emitted);
  const original = ts.isTypeAliasDeclaration(statement)
    ? source.statements.find(
        (node) => ts.isTypeAliasDeclaration(node) && node.name.text === name,
      )
    : null;
  const literals =
    original && !isLiteralUnionNode(original.type)
      ? literalUnion(checker, original)
      : null;
  if (literals) {
    body = `${/^export\b/.test(body) ? "export " : ""}type ${name} =${literals};`;
    leading ||= documentation(checker, original) ?? "";
  } else if (ts.isFunctionDeclaration(statement)) {
    // Destructured parameters only repeat prop names; one named parameter reads better and
    // avoids renamed bindings, which are not valid outside a declaration file.
    const start = statement.getStart(emitted);
    for (const parameter of [...statement.parameters].reverse()) {
      if (ts.isIdentifier(parameter.name)) continue;
      body =
        body.slice(0, parameter.name.getStart(emitted) - start) +
        "props" +
        body.slice(parameter.name.getEnd() - start);
    }
  }
  body = body.replace(/^export declare /, "export ").replace(/^declare /, "");
  if (isValue && !exported.has(name)) body = body.replace(/^export /, "");
  // TypeScript emits four-space indents; the copied source types use two, as the app does.
  body = body.replace(/^((?: {4})+)/gm, (spaces) =>
    " ".repeat(spaces.length / 2),
  );

  const queries = new Set();
  if (!literals) {
    const visit = (node) => {
      if (ts.isTypeQueryNode(node)) {
        queries.add(node.exprName.getText(emitted).split(".")[0]);
      }
      ts.forEachChild(node, visit);
    };
    visit(statement);
  }
  return {
    name,
    hidden: isValue && !exported.has(name),
    queries,
    text: leading ? `${leading}\n${body}` : body,
  };
}

function isLiteralUnionNode(node) {
  if (!node) return false;
  const members = ts.isUnionTypeNode(node) ? node.types : [node];
  return members.every(
    (member) =>
      ts.isLiteralTypeNode(member) &&
      (ts.isStringLiteral(member.literal) ||
        ts.isNumericLiteral(member.literal) ||
        ts.isPrefixUnaryExpression(member.literal)),
  );
}

// The members of an alias that resolves to a union of string or number literals, in the order
// its source lists them, or null for any other type.
function literalUnion(checker, declaration) {
  const type = checker.getTypeAtLocation(declaration.name);
  const members = type.isUnion() ? type.types : [type];
  if (!members.every((member) => member.isLiteral())) return null;
  const values = members.map((member) => member.value);
  if (values.some((value) => typeof value === "object")) return null;
  const order = declaredOrder(checker, declaration);
  const position = (value) =>
    order.includes(value) ? order.indexOf(value) : order.length;
  values.sort((first, second) => position(first) - position(second));
  const written = values.map((value) => JSON.stringify(value));
  const line = ` ${written.join(" | ")}`;
  return line.length <= 72
    ? line
    : written.map((value) => `\n  | ${value}`).join("");
}

// The checker orders union members by when it first met each literal, so the order comes from
// the source: a written union, or the list a union such as (typeof badgeTones)[number] reads.
function declaredOrder(checker, declaration) {
  const literal = (node) => {
    if (ts.isStringLiteralLike(node)) return [node.text];
    if (ts.isNumericLiteral(node) || ts.isPrefixUnaryExpression(node)) {
      return [Number(node.getText())];
    }
    return [];
  };
  let node = declaration.type;
  if (isLiteralUnionNode(node)) {
    return (ts.isUnionTypeNode(node) ? node.types : [node]).flatMap((member) =>
      literal(member.literal),
    );
  }
  if (!node || !ts.isIndexedAccessTypeNode(node)) return [];
  node = node.objectType;
  while (ts.isParenthesizedTypeNode(node)) node = node.type;
  if (!ts.isTypeQueryNode(node)) return [];
  const value = checker.getSymbolAtLocation(node.exprName)?.valueDeclaration;
  let list =
    value && ts.isVariableDeclaration(value) ? value.initializer : null;
  while (
    list &&
    (ts.isAsExpression(list) ||
      ts.isSatisfiesExpression(list) ||
      ts.isParenthesizedExpression(list))
  ) {
    list = list.expression;
  }
  if (!list || !ts.isArrayLiteralExpression(list)) return [];
  return list.elements.flatMap(literal);
}

// Copies the types that components import from the rest of the app, such as the unions generated
// from the component specs, with the app types each copy references in turn.
//
// An alias that is a union of literals is written out as that union, so index.d.ts shows the
// values instead of the generated list they come from. Any other alias or interface is copied as
// written. A copy keeps its source's JSDoc, or that of the value its source reads with `typeof`.
function copier({ program, checker, webRoot, declared, reactImports }) {
  const appRoot = resolve(webRoot);
  const declarations = [];
  const origins = new Map();

  const resolveAlias = (symbol) =>
    symbol && symbol.flags & ts.SymbolFlags.Alias
      ? checker.getAliasedSymbol(symbol)
      : symbol;

  function add({ file, specifier, module, imported, local }) {
    const source = module && program.getSourceFile(module);
    const symbol = resolveAlias(
      source && checker.getSymbolAtLocation(source)?.exports?.get(imported),
    );
    copy(symbol, local, `${file} imports ${imported} from ${specifier}`);
  }

  function copy(symbol, local, context) {
    const declaration = symbol?.declarations?.find(
      (node) =>
        ts.isTypeAliasDeclaration(node) || ts.isInterfaceDeclaration(node),
    );
    if (!declaration) {
      throw new Error(
        `${context}, which is not a type alias or interface index.d.ts can copy.`,
      );
    }
    const source = declaration.getSourceFile();
    const origin = `${relative(appRoot, source.fileName)}#${symbol.name}`;
    if (origins.has(local)) {
      if (origins.get(local) === origin) return;
      throw new Error(
        `${context}, but index.d.ts already copies ${origins.get(local)} as ${local}.`,
      );
    }
    origins.set(local, origin);
    record(declared, local, origin);

    const literals = ts.isTypeAliasDeclaration(declaration)
      ? literalUnion(checker, declaration)
      : null;
    let body;
    if (literals) {
      body = `export type ${local} =${literals};`;
    } else {
      for (const dependency of references(declaration, `${origin}`)) {
        copy(dependency, dependency.name, `${origin} uses ${dependency.name}`);
      }
      const text = declaration
        .getText(source)
        .replace(/^export\s+/, "")
        .replace(/^(type|interface)\s+\w+/, `$1 ${local}`);
      body = `export ${text}`;
    }
    const comment = documentation(checker, declaration);
    declarations.push(comment ? `${comment}\n${body}` : body);
  }

  // The app types a copied declaration names, after noting the React types it needs.
  function references(declaration, origin) {
    const found = [];
    const visit = (node) => {
      if (ts.isTypeQueryNode(node)) {
        throw new Error(
          `${origin} reads the value ${node.exprName.getText()} with typeof, which index.d.ts cannot declare. Make it a union of literals or a plain type.`,
        );
      }
      const name = ts.isTypeReferenceNode(node)
        ? node.typeName
        : ts.isExpressionWithTypeArguments(node)
          ? node.expression
          : null;
      const symbol = name && resolveAlias(checker.getSymbolAtLocation(name));
      const target = symbol?.declarations?.[0];
      if (target && !ts.isTypeParameterDeclaration(target)) {
        const file = target.getSourceFile();
        const where = resolve(file.fileName);
        if (program.isSourceFileDefaultLibrary(file)) {
          // A global such as Record or HTMLElement.
        } else if (
          ts.isIdentifier(name) &&
          name.text === symbol.name &&
          /[\\/]node_modules[\\/]@types[\\/]react[\\/]/.test(where)
        ) {
          reactImports.add(name.text);
        } else if (
          ts.isIdentifier(name) &&
          name.text === symbol.name &&
          where.startsWith(`${appRoot}/`) &&
          !where.includes("/node_modules/")
        ) {
          found.push(symbol);
        } else {
          throw new Error(
            `${origin} uses ${name.getText()} from ${relative(appRoot, where)}, which index.d.ts cannot reference. Import it by its own name, or give the type a plain definition.`,
          );
        }
      }
      ts.forEachChild(node, visit);
    };
    ts.forEachChild(declaration, visit);
    return found;
  }

  return { add, declarations };
}

// A type's JSDoc, or that of the value it reads with typeof, such as the generated badgeTones.
function documentation(checker, declaration) {
  const own = jsDoc(declaration);
  if (own) return own;
  let comment = null;
  const visit = (node) => {
    if (comment) return;
    if (ts.isTypeQueryNode(node)) {
      const value = checker.getSymbolAtLocation(
        node.exprName,
      )?.valueDeclaration;
      comment = value ? jsDoc(value) : null;
    }
    ts.forEachChild(node, visit);
  };
  ts.forEachChild(declaration, visit);
  return comment;
}

function jsDoc(node) {
  const comments = ts.getJSDocCommentsAndTags(node).filter(ts.isJSDoc);
  return comments.at(-1)?.getText() ?? null;
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
    // A union of literals keeps the order index.d.ts writes it in; the checker would order its
    // members by when it first met each literal.
    const reference = declarations.find(
      (declaration) =>
        declaration.type && ts.isTypeReferenceNode(declaration.type),
    )?.type;
    const alias = reference
      ? checker.getSymbolAtLocation(reference.typeName)?.declarations?.[0]
      : null;
    if (alias && ts.isTypeAliasDeclaration(alias)) {
      const members = ts.isUnionTypeNode(alias.type)
        ? alias.type.types
        : [alias.type];
      if (members.every((member) => ts.isLiteralTypeNode(member))) {
        return members.map((member) => member.getText()).join(" | ");
      }
    }
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

// Defaults live in the source's destructuring, which declarations drop. A default read from a
// constant, such as badgeDefaults.size, is shown as the literal it resolves to.
function readDefaults(program, checker, components, componentDirectory) {
  const written = (initializer, source) => {
    const type = checker.getTypeAtLocation(initializer);
    if (type.isStringLiteral()) return JSON.stringify(type.value);
    if (type.isNumberLiteral()) return String(type.value);
    if (type.flags & ts.TypeFlags.BooleanLiteral) {
      return checker.typeToString(type);
    }
    return initializer.getText(source);
  };
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
          values[key.replace(/^"|"$/g, "")] = written(
            element.initializer,
            source,
          );
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
