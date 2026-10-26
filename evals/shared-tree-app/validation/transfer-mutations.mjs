import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { substitute } from "./mutations.mjs";

export const transferMutations = {
  "transfer-copy": { failed: "transfers.identity", after: "transfers.local" },
  "transfer-stale-index": { failed: "transfers.local" },
};

export async function applyTransferMutation({ sdk, defect, workspace }) {
  if (!["fluid", "watershed"].includes(sdk)) throw new TypeError(`Unknown SDK: ${sdk}`);
  if (!Object.hasOwn(transferMutations, defect)) throw new TypeError(`Unknown transfer mutation: ${defect}`);
  const path = join(workspace, sdk === "fluid" ? "src/model.ts" : "src/incident_eval/model.gleam");
  let model = await readFile(path, "utf8");
  if (defect === "transfer-stale-index") {
    model = substitute(model, "transfer-lookup", sdk === "fluid"
      ? "const sourceIndex = 0;"
      : `use _, source <- with_step(tree, incident, id)
      use candidate <- result.try(t.array_node(source, 0))
      use node <- result.try(case candidate {
        Some(node) -> Ok(node)
        None -> Error(invalid("Step does not exist"))
      })`);
  } else {
    model = substitute(model, "transfer-move", sdk === "fluid"
      ? `const gap = action.before === null ? destination.steps.length
              : [...destination.steps].findIndex(node => node.id === action.before);
            if (gap < 0) throw new Error("Destination is not a sibling");
            const value = { id: step.id, label: step.label, done: step.done };
            incident.steps.removeAt(sourceIndex);
            destination.steps.insertAt(gap, value);`
      : `use value <- result.try(t.read(node))
      use values <- result.try(t.read(destination))
      use gap <- result.try(case before {
        None -> Ok(list.length(values))
        Some(sibling) -> {
          use sibling <- result.try(t.read(sibling))
          Ok(list.length(list.take_while(values, fn(value) {
            value.id != sibling.id
          })))
        }
      })
      use _ <- result.try(t.array_remove_node(source, node))
      t.array_insert(destination, gap, [value])`);
  }
  await writeFile(path, model);
}
