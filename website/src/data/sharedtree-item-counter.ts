import { sourceSnippet, withSourceUrl, type Snippet } from "../lib/snippet.ts";

export interface ItemCounterComparisonRow {
  id: "schema" | "lifecycle" | "observe" | "edits";
  title: string;
  explanation: string;
  fluid: readonly Snippet[];
  watershed: readonly Snippet[];
}

export const upstreamCommit =
  "396454d692950f29c9965cf1190678cc6a227d23";

const examplePrefix = "examples/shared_tree_item_counter_lustre/";

function fluidSnippet(snippet: Snippet): Snippet {
  const originalPath = snippet.sourcePath.slice(`${examplePrefix}upstream/`.length);
  return withSourceUrl(snippet,
    `https://github.com/microsoft/FluidExamples/blob/${upstreamCommit}/item-counter/${originalPath}`);
}

function watershedSnippet(snippet: Snippet): Snippet {
  return withSourceUrl(snippet,
    `https://github.com/tylerbutler/watershed/blob/main/${snippet.sourcePath}`);
}

export const itemCounterRows: readonly ItemCounterComparisonRow[] = [
  {
    id: "schema",
    title: "Start with the same array.",
    explanation:
      "Fluid derives a typed StringArray class from SchemaFactory. watershed declares a checked stored schema and a view schema, then reads TreeValue snapshots. The serialized schema below is real application code, not hidden setup.",
    fluid: [fluidSnippet(sourceSnippet("item-counter-fluid-schema"))],
    watershed: [watershedSnippet(sourceSnippet("item-counter-watershed-schema"))],
  },
  {
    id: "lifecycle",
    title: "Same empty root. Different way in.",
    explanation:
      "Fluid creates or loads a container, gets its tree view, initializes it if allowed, and attaches a new detached container. watershed creates a native container with the schema and initial root, keeps the returned ID, then connects and opens the tree. These are excerpts from the complete applications; surrounding configuration and UI setup stay in the linked source.",
    fluid: [
      fluidSnippet(sourceSnippet("item-counter-fluid-container")),
      fluidSnippet(sourceSnippet("item-counter-fluid-view")),
    ],
    watershed: [
      watershedSnippet(sourceSnippet("item-counter-watershed-create")),
      watershedSnippet(sourceSnippet("item-counter-watershed-open")),
    ],
  },
  {
    id: "observe",
    title: "Let the tree tell the view.",
    explanation:
      "Both apps derive the count from the array, not from button clicks. React listens for nodeChanged and reads length. Lustre subscribes to the native tree, reads a snapshot, checks its shape, and counts its entries. Both unsubscribe when their view closes; the complete Gleam app also handles a subscription delivered after Close.",
    fluid: [fluidSnippet(sourceSnippet("item-counter-fluid-observe"))],
    watershed: [watershedSnippet(sourceSnippet("item-counter-watershed-observe"))],
  },
  {
    id: "edits",
    title: "Insert an entry. Remove the first.",
    explanation:
      "Fluid's methods edit the array directly. watershed prepares an explicit edit against the latest checked snapshot, then submits it through the native facade. Both insert an empty string at index zero and leave an empty array alone on Remove. watershed's remove range is half-open: [0, 1).",
    fluid: [fluidSnippet(sourceSnippet("item-counter-fluid-edits"))],
    watershed: [
      watershedSnippet(sourceSnippet("item-counter-watershed-edits")),
      watershedSnippet(sourceSnippet("item-counter-watershed-apply")),
    ],
  },
];
