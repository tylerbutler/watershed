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
    title: "Define the array schema.",
    explanation:
      "Fluid derives a typed StringArray class from SchemaFactory and passes it to TreeViewConfiguration. In watershed, configuration() declares the array schema as Root(List(String)). Pass this declaration to the create or open API. These APIs compile the stored schema, view schema, and snapshot codecs.",
    fluid: [fluidSnippet(sourceSnippet("item-counter-fluid-schema"))],
    watershed: [watershedSnippet(sourceSnippet("item-counter-watershed-schema"))],
  },
  {
    id: "lifecycle",
    title: "Create or open a container.",
    explanation:
      "Fluid creates or loads a container and gets its tree view. It initializes the tree if allowed and attaches a new detached container. watershed passes configuration() and an empty list to create_dev, then saves the returned ID. It connects and opens a Tree(List(String)) with the same declaration. Opening does not initialize content or upgrade the stored schema. The complete applications include configuration and UI setup that these excerpts omit.",
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
    title: "Read the array and subscribe to changes.",
    explanation:
      "Both applications calculate the count from the array length. The React application subscribes to nodeChanged and reads length. The Lustre application uses observe to subscribe and read_root to request the initial values. Both Gleam operations deliver Result(List(String), error.Error); observe checks that the root is readable but sends no initial value. Subscription registration can also fail. Both applications unsubscribe when their view closes; the complete Gleam application also handles a subscription that arrives after Close.",
    fluid: [fluidSnippet(sourceSnippet("item-counter-fluid-observe"))],
    watershed: [watershedSnippet(sourceSnippet("item-counter-watershed-observe"))],
  },
  {
    id: "edits",
    title: "Insert or remove the first entry.",
    explanation:
      "Fluid methods edit the array. watershed calls required_root to get a Ref(List(String)), then passes it to array_insert or array_remove. The tree uses the item codec from its declaration, so the caller does not prepare a separate edit value. Both applications insert an empty string at index zero; Remove has no effect on an empty array. watershed checks for the first entry with array_get. To remove the first entry, pass start index 0 and end index 1. The end index is excluded.",
    fluid: [fluidSnippet(sourceSnippet("item-counter-fluid-edits"))],
    watershed: [
      watershedSnippet(sourceSnippet("item-counter-watershed-edits")),
      watershedSnippet(sourceSnippet("item-counter-watershed-apply")),
    ],
  },
];
