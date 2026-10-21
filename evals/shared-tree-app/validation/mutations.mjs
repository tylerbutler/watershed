import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

export const mutations = {
  "local-only": { failed: ["local.incident-create"], after: "native.schema" },
  "serialized-root": { failed: ["native.schema"], after: "integrity.build" },
  "replace-subtree": { failed: ["native.property-edits"], after: "native.optional" },
  "stale-index": { failed: ["identity.target"], after: "collaboration.remote" },
  "ignore-remote": { failed: ["native.property-edits"], after: "native.optional" },
  "reset-on-open": { failed: ["lifecycle.no-reset"], after: "concurrency.barrier" },
  "leak-subscription": { failed: ["lifecycle.close"], after: "local.invalid-input" },
  "edit-shell": { failed: ["integrity.assets"], after: "integrity.sdk" },
};

export function substitute(source, name, replacement) {
  const start = `// mutation:start ${name}\n`;
  const end = `// mutation:end ${name}`;
  const from = source.indexOf(start);
  const to = source.indexOf(end);
  if (from < 0 || to < from + start.length ||
      source.indexOf(start, from + start.length) !== -1 ||
      source.indexOf(end, to + end.length) !== -1) {
    throw new Error(`Expected exactly one ordered mutation hook: ${name}`);
  }
  return source.slice(0, from + start.length) + replacement + "\n" + source.slice(to);
}

export async function applyMutation({ sdk, defect, workspace }) {
  if (!["watershed", "fluid"].includes(sdk)) throw new TypeError(`Unknown SDK: ${sdk}`);
  if (!Object.hasOwn(mutations, defect)) throw new TypeError(`Unknown mutation: ${defect}`);
  if (defect === "edit-shell") {
    const path = join(workspace, "index.html");
    await writeFile(path, (await readFile(path, "utf8")) + "\n<!-- Modified protected shell -->\n");
    return;
  }
  const directory = join(workspace, sdk === "fluid" ? "src" : "src/incident_eval");
  const extension = sdk === "fluid" ? "ts" : "gleam";
  const modelPath = join(directory, `model.${extension}`);
  const schemaPath = join(directory, `schema.${extension}`);
  let model = await readFile(modelPath, "utf8");
  let schema = await readFile(schemaPath, "utf8");
  const hook = (name, body) => { model = substitute(model, name, body); };
  const boardSection = async name => {
    const source = await readFile(new URL("./fixtures/mutation_board.gleam", import.meta.url), "utf8");
    return source.split(`// fixture:start ${name}\n`)[1].split(`// fixture:end ${name}`)[0];
  };
  if (sdk === "fluid") {
    switch (defect) {
      case "local-only":
        hook("root", `private readonly localRoot = new BoardNode({ incidents: [] });
  private get root() { return this.localRoot; }`);
        hook("apply", `apply(action: Action) { this.edit(action); this.emit(); }
  private edit(action: Action) {`);
        break;
      case "serialized-root":
        schema = substitute(schema, "board-schema", "serialized: schema.string,");
        model = await readFile(new URL("./fixtures/fluid-serialized-root.ts", import.meta.url), "utf8");
        break;
      case "replace-subtree":
        hook("title", `case "title":
        {
          const index = [...this.root.incidents].indexOf(incident);
          const value = this.read().board.incidents[index];
          this.root.incidents.removeAt(index);
          this.root.incidents.insertAt(index, new IncidentNode({ ...value, title: action.value }));
        }
        break;`);
        break;
      case "stale-index":
        hook("root", `private get root() { return this.view.root; }
  private readonly indices = new Map<string, number>();`);
        hook("lookup", `const nodes = [...this.root.incidents];
    if (!this.indices.has(id)) this.indices.set(id, nodes.findIndex(node => node.id === id));
    return nodes[this.indices.get(id)!];`);
        hook("target", `const target = "incident" in action ? action.incident : action.id;
    const incident = action.type === "title" ? this.incident(target)
      : [...this.root.incidents].find(node => node.id === target);`);
        break;
      case "ignore-remote":
        hook("observation", "");
        hook("apply", `apply(action: Action) { this.edit(action); this.emit(); }
  private edit(action: Action) {`);
        break;
      case "reset-on-open":
        hook("constructor", `constructor(container: IFluidContainer, view: TreeView<typeof BoardNode>,
    readonly documentId: string, private resetOnOpen: boolean) {`);
        hook("session", "return new BoardSession(container, view, id, !creating);");
        hook("read", `if (phase === "ready" && this.resetOnOpen) {
          this.resetOnOpen = false;
          for (const incident of this.root.incidents) incident.assignee = undefined;
        }`);
        break;
      case "leak-subscription": hook("cleanup", ""); break;
    }
  } else {
    switch (defect) {
      case "local-only":
        hook("apply", `case model.state.phase {
    d.Ready -> #(
      Model(..model, state: d.State(..model.state,
        board: mutation_apply(model.state.board, action))),
      effect.none(),
    )
    _ -> #(model, effect.none())
  }`);
        model += "\n" + await boardSection("actions");
        break;
      case "serialized-root":
        hook("edit", `use board <- result.try(t.read_root(tree))
  t.replace_root(tree, mutation_apply(board, action))`);
        model += "\n" + await boardSection("actions");
        schema = substitute(schema, "imports", "import gleam/json\nimport gleam/dynamic/decode");
        schema = substitute(schema, "board-schema", `let serialized = b.required(
    "serialized", b.string(), fn(board: d.Board) { mutation_encode(board) },
  )
  b.object(factory(), "Board", [b.property(serialized)], fn(reader) {
    use text <- result.try(b.read_property(reader, serialized))
    mutation_decode(text)
  }) |> b.root`);
        schema += "\n" + await boardSection("codec");
        break;
      case "replace-subtree":
        hook("title", `d.Title(id, value) -> {
      use node, array <- with_incident(tree, id)
      use incident <- result.try(t.read(node))
      use values <- result.try(t.read(array))
      let index = values
        |> list.index_map(fn(v, index) { #(v.id, index) })
        |> list.key_find(id)
        |> result.unwrap(0)
      use _ <- result.try(t.array_remove_node(array, node))
      t.array_insert(array, index, [d.Incident(..incident, title: value)])
    }`);
        break;
      case "stale-index":
        hook("fields", "mutation_indices: List(#(String, Int)),");
        hook("init", `let model =
    Model(config, d.State(d.Opening, None, d.Board([]), []), None, None, None, [])`);
        hook("apply", `let #(model, action) = case action {
    d.Title(id, value) -> {
      let index = case list.key_find(model.mutation_indices, id) {
        Ok(index) -> index
        Error(_) -> model.state.board.incidents
          |> list.index_map(fn(incident, index) { #(incident.id, index) })
          |> list.key_find(id)
          |> result.unwrap(-1)
      }
      let target = model.state.board.incidents
        |> list.drop(index)
        |> list.first
        |> result.map(fn(incident) { incident.id })
        |> result.unwrap(id)
      #(
        Model(..model, mutation_indices: [#(id, index), ..model.mutation_indices]),
        d.Title(target, value),
      )
    }
    _ -> #(model, action)
  }
  case model.state.phase, model.tree {
    d.Ready, Some(tree) -> #(
      model,
      effects.perform(fn() { edit(tree, action) }, Edited),
    )
    _, _ -> #(model, effect.none())
  }`);
        break;
      case "ignore-remote":
        hook("open", `_, Opened(Ok(tree)) -> #(
      Model(..model, tree: Some(tree)),
      effects.read_root(tree, Changed),
    )`);
        break;
      case "reset-on-open":
        hook("open", `_, Opened(Ok(tree)) -> {
      let _ = case t.read_root(tree) {
        Ok(board) -> list.each(board.incidents, fn(incident) {
          let _ = with_incident(tree, incident.id, fn(node, _) {
            t.set(node, s.assignee(), None)
          })
          Nil
        })
        Error(_) -> Nil
      }
      #(
        Model(..model, tree: Some(tree)),
        effects.observe(tree, Subscribed, Changed),
      )
    }`);
        break;
      case "leak-subscription": hook("cleanup", "effect.none()"); break;
    }
  }
  await writeFile(modelPath, model);
  await writeFile(schemaPath, schema);
}
