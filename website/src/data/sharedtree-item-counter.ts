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
      "Fluid derives a typed StringArray class from SchemaFactory and passes it to TreeViewConfiguration. In watershed, configuration() declares the same shape as Root(List(String)). Pass it to create or open; those APIs compile the stored schema, view schema, and snapshot codecs for you.",
    fluid: [fluidSnippet(sourceSnippet("item-counter-fluid-schema"))],
    watershed: [watershedSnippet(sourceSnippet("item-counter-watershed-schema"))],
  },
  {
    id: "lifecycle",
    title: "Same empty root. Different way in.",
    explanation:
      "Fluid creates or loads a container, gets its tree view, initializes it if allowed, and attaches a new detached container. watershed passes configuration() and an ordinary empty list to create_dev, keeps the returned ID, then connects and opens a Tree(List(String)) with the same declaration. Opening doesn't initialize content or upgrade the stored schema. These are excerpts from the complete applications; surrounding configuration and UI setup stay in the linked source.",
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
      "Both apps derive the count from the array, not from button clicks. React listens for nodeChanged and reads length. Lustre registers observe and requests the initial snapshot with read_root. Both deliver Result(List(String), error.Error), so the app can count the entries without another decoder. Observation checks that the root is readable but sends no initial value. Registration can fail too. Both apps unsubscribe when their view closes; the complete Gleam app also handles a subscription delivered after Close.",
    fluid: [fluidSnippet(sourceSnippet("item-counter-fluid-observe"))],
    watershed: [watershedSnippet(sourceSnippet("item-counter-watershed-observe"))],
  },
  {
    id: "edits",
    title: "Insert an entry. Remove the first.",
    explanation:
      "Fluid's methods edit the array directly. watershed calls required_root to acquire a Ref(List(String)), then passes it to array_insert or array_remove. The tree retains the item codec from its declaration; there's no intermediate edit value to prepare or dispatch. Both insert an empty string at index zero and leave an empty array alone on Remove. watershed checks for the first entry with array_get, and its remove range is half-open: [0, 1).",
    fluid: [fluidSnippet(sourceSnippet("item-counter-fluid-edits"))],
    watershed: [
      watershedSnippet(sourceSnippet("item-counter-watershed-edits")),
      watershedSnippet(sourceSnippet("item-counter-watershed-apply")),
    ],
  },
];
