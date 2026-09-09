import ts from "typescript";
import { extname } from "node:path";
import { makeSymbol, rangeAt, sortSymbols } from "./symbols.mjs";

export function parseJavaScript({ path, source, scriptKind }) {
  const extension = scriptKind ?? extname(path).slice(1);
  const kind = extension === "tsx" ? ts.ScriptKind.TSX : extension === "jsx" ? ts.ScriptKind.JSX
    : ["ts", "mts", "cts"].includes(extension) ? ts.ScriptKind.TS : ts.ScriptKind.JS;
  const file = ts.createSourceFile(path, source, ts.ScriptTarget.Latest, true, kind);
  const diagnostics = file.parseDiagnostics.map((d) => ({
    path, message: ts.flattenDiagnosticMessageText(d.messageText, "\n"),
    range: rangeAt(source, d.start ?? 0, (d.start ?? 0) + (d.length ?? 0)),
  }));
  if (diagnostics.length) return { symbols: [], diagnostics, skippedRegions: [] };
  const symbols = [];
  const exports = new Set();
  for (const node of file.statements) {
    if (ts.isExportDeclaration(node) && !node.moduleSpecifier && node.exportClause && ts.isNamedExports(node.exportClause)) {
      for (const item of node.exportClause.elements) exports.add((item.propertyName ?? item.name).text);
    }
    if (ts.isExportAssignment(node) && ts.isIdentifier(node.expression)) exports.add(node.expression.text);
  }
  const hasModifier = (node, modifier) => node.modifiers?.some((m) => m.kind === modifier) ?? false;
  function staticName(node) {
    if (!node) return null;
    if (ts.isIdentifier(node) || ts.isPrivateIdentifier(node) || ts.isStringLiteral(node) || ts.isNumericLiteral(node)) return node.text;
    if (ts.isComputedPropertyName(node) && (ts.isStringLiteral(node.expression) || ts.isNumericLiteral(node.expression))) return node.expression.text;
    return null;
  }
  function add(node, name, kind, scope, signatureEnd, declaration = node) {
    const start = declaration.getStart(file);
    let exportNode = declaration;
    if (ts.isVariableDeclaration(declaration)) exportNode = declaration.parent.parent;
    const exported = scope.length === 0 && (exports.has(name)
      || hasModifier(exportNode, ts.SyntaxKind.ExportKeyword) || hasModifier(exportNode, ts.SyntaxKind.DefaultKeyword));
    const visibility = name.startsWith("#") || hasModifier(node, ts.SyntaxKind.PrivateKeyword) ? "private"
      : hasModifier(node, ts.SyntaxKind.ProtectedKeyword) ? "protected"
      : exported || kind === "method" ? "public" : "local";
    const isVariable = ts.isVariableDeclaration(declaration);
    // Include const/let only for the first declarator; each subsequent name still has its own range.
    const declarationStart = isVariable && declaration.parent.declarations[0] === declaration
      ? declaration.parent.getStart(file) : start;
    symbols.push(makeSymbol(path, source, {
      name, kind, container: scope, start: declarationStart, end: declaration.end,
      signatureEnd, visibility, exported,
    }));
  }
  const callable = (node) => ts.isArrowFunction(node) || ts.isFunctionExpression(node);
  function visit(node, scope) {
    let childScope = scope;
    if (ts.isFunctionDeclaration(node) && node.name) {
      add(node, node.name.text, "function", scope, node.body?.getStart(file) ?? node.end);
      childScope = [...scope, node.name.text];
    } else if (ts.isVariableDeclaration(node)) {
      const name = staticName(node.name);
      if (name) {
        if (node.initializer && callable(node.initializer)) {
          add(node.initializer, name, "function", scope, node.initializer.body.getStart(file), node);
          childScope = [...scope, name];
        } else if (node.initializer && ts.isClassExpression(node.initializer)) {
          add(node.initializer, name, "class", scope, classHeaderEnd(node.initializer), node);
          childScope = [...scope, name];
        } else {
          if (scope.length === 0 && ts.isVariableDeclarationList(node.parent)
              && (node.parent.flags & ts.NodeFlags.Const) && ts.isSourceFile(node.parent.parent.parent)) {
            add(node, name, "constant", scope, node.type?.end ?? node.name.end);
          }
          if (node.initializer && ts.isObjectLiteralExpression(node.initializer)) childScope = [...scope, name];
        }
      }
    } else if (ts.isClassDeclaration(node) || ts.isClassExpression(node)) {
      const bound = ts.isVariableDeclaration(node.parent) || ts.isPropertyAssignment(node.parent);
      const name = node.name?.text ?? (hasModifier(node, ts.SyntaxKind.DefaultKeyword) ? "default" : null);
      if (name && !bound) {
        add(node, name, "class", scope, classHeaderEnd(node));
        childScope = [...scope, name];
      }
    } else if (ts.isConstructorDeclaration(node) || ts.isMethodDeclaration(node)
        || ts.isGetAccessorDeclaration(node) || ts.isSetAccessorDeclaration(node)
        || ts.isMethodSignature(node)) {
      const name = ts.isConstructorDeclaration(node) ? "constructor" : staticName(node.name);
      if (name) {
        add(node, name, "method", scope, node.body?.getStart(file) ?? node.end);
        childScope = [...scope, name];
      }
    } else if (ts.isPropertyAssignment(node) || ts.isPropertyDeclaration(node)) {
      const name = staticName(node.name);
      if (name && node.initializer && callable(node.initializer)) {
        add(node, name, "method", scope, node.initializer.body.getStart(file));
        childScope = [...scope, name];
      } else if (name && node.initializer && ts.isObjectLiteralExpression(node.initializer)) {
        childScope = [...scope, name];
      }
    } else if (ts.isFunctionExpression(node)) {
      const bound = ts.isVariableDeclaration(node.parent) || ts.isPropertyAssignment(node.parent) || ts.isPropertyDeclaration(node.parent);
      if (node.name && !bound) {
        add(node, node.name.text, "function", scope, node.body.getStart(file));
        childScope = [...scope, node.name.text];
      }
    } else if (ts.isInterfaceDeclaration(node) || ts.isTypeAliasDeclaration(node) || ts.isEnumDeclaration(node)) {
      const end = ts.isTypeAliasDeclaration(node) ? node.end : classHeaderEnd(node);
      add(node, node.name.text, "type", scope, end);
      childScope = [...scope, node.name.text];
    }
    ts.forEachChild(node, (child) => visit(child, childScope));
  }
  function classHeaderEnd(node) {
    return node.getChildren(file).find((n) => n.kind === ts.SyntaxKind.OpenBraceToken)?.getStart(file) ?? node.end;
  }
  visit(file, []);
  return { symbols: sortSymbols(symbols), diagnostics: [], skippedRegions: [] };
}
