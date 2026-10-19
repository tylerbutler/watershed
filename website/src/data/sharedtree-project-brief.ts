import { sourceSnippet, withSourceUrl, type Snippet } from "../lib/snippet.ts";

export interface ProjectBriefComparisonRow {
  id: "schema" | "lifecycle" | "observe" | "edits" | "milestones" | "presence";
  title: string;
  explanation: string;
  fluid: readonly Snippet[];
  watershed: readonly Snippet[];
}

function localSnippet(snippet: Snippet): Snippet {
  return withSourceUrl(snippet,
    `https://github.com/tylerbutler/watershed/blob/main/${snippet.sourcePath}`);
}

export const projectBriefRows: readonly ProjectBriefComparisonRow[] = [
  {
    id: "schema",
    title: "A brief is an object, not a bag of fields.",
    explanation:
      "Owner and schedule are nested objects; review is optional, and schedule.milestones is the only array. Fluid declares live node classes with SchemaFactory. watershed declares typed properties and a Root(ProjectBrief); its constructors decode immutable Gleam values. The excerpts show the root, optional review, and nested schedule—the linked modules contain the remaining property declarations. This is native SharedTree, not a SharedSequence pretending to enforce the same nested schema.",
    fluid: [localSnippet(sourceSnippet("project-brief-fluid-schema"))],
    watershed: [localSnippet(sourceSnippet("project-brief-watershed-schema"))],
  },
  {
    id: "lifecycle",
    title: "Open once. Close what you opened.",
    explanation:
      "Fluid creates or loads a container, initializes only a new tree, and attaches before publishing its URL. watershed creates with the schema and initial values, then connects and opens with the same declaration. The Gleam update branches open the tree and register change notifications; neither app reinitializes a loaded brief or silently upgrades its schema. The complete apps dispose subscriptions, views, presence, and connections on Close, including resources that arrive late. An uncertain create or attach is an error, never an automatic retry.",
    fluid: [
      localSnippet(sourceSnippet("project-brief-fluid-lifecycle")),
      localSnippet(sourceSnippet("project-brief-fluid-lifecycle-close")),
    ],
    watershed: [
      localSnippet(sourceSnippet("project-brief-watershed-lifecycle")),
      localSnippet(sourceSnippet("project-brief-watershed-lifecycle-open")),
    ],
  },
  {
    id: "observe",
    title: "A live node and a snapshot aren't the same thing.",
    explanation:
      "Fluid keeps the live view.root and listens for treeChanged and rootChanged; its session notifies React to read those live nodes again. watershed subscribes to changes, captures an initial read after registration, and captures again on each notification. read_root returns an immutable ProjectBrief snapshot: yesterday's value won't change under your feet. capture pairs that value with live Ref handles for edits. Failed reads stay errors, not empty forms; duplicate milestone IDs invalidate the form rather than aliasing two rows.",
    fluid: [localSnippet(sourceSnippet("project-brief-fluid-observe"))],
    watershed: [localSnippet(sourceSnippet("project-brief-watershed-observe"))],
  },
  {
    id: "edits",
    title: "Change the property. Keep the object.",
    explanation:
      "Typing a name assigns owner.name on the existing owner node—it doesn't replace owner or rebuild the brief. Fluid's assign helper checks that the captured node still belongs to this brief before assigning its property. Gleam's captured Ref and schema property go straight to shared_tree.set. That leaves an email edit on the same owner, or a target-date edit on schedule, independent. Two writers to the same string still contend over a whole-string assignment; there is no character-level merge.",
    fluid: [localSnippet(sourceSnippet("project-brief-fluid-edits"))],
    watershed: [localSnippet(sourceSnippet("project-brief-watershed-edits"))],
  },
  {
    id: "milestones",
    title: "The row moves. Its identity doesn't.",
    explanation:
      "Every inserted milestone gets a fresh UUID in its application id, which the apps never edit. Both render keyed rows and address field selection by that ID, not an array index. Edits capture the actual node; watershed removes through array_remove_node, while Fluid finds the captured node's current index immediately before removal. Remove an earlier row while someone types and the input, caret, and badge stay with their milestone. Removed-node actions fail rather than touching a neighbor; there are no reorder controls.",
    fluid: [
      localSnippet(sourceSnippet("project-brief-fluid-milestones")),
      localSnippet(sourceSnippet("project-brief-fluid-milestones-view")),
    ],
    watershed: [
      localSnippet(sourceSnippet("project-brief-watershed-milestones")),
      localSnippet(sourceSnippet("project-brief-watershed-milestones-view")),
    ],
  },
  {
    id: "presence",
    title: "Who's here isn't part of the brief.",
    explanation:
      "Fluid uses the experimental Signaler exported by @fluid-experimental/data-objects 3.1.0, alongside SharedTree. watershed explicitly configures presence.Ripple and updates the presence handle on focus. These announcements travel outside the durable tree operation stream: no tree edit, commit, or saved summary. Selection is transient and advisory, never a lock. Session-attributed names use a two-second heartbeat and a 6.5-second expiry window. Reconnect accepts fresh awareness; removed milestones and removed or replaced review objects invalidate stale selections so old badges can't attach to new objects.",
    fluid: [localSnippet(sourceSnippet("project-brief-fluid-presence"))],
    watershed: [
      localSnippet(sourceSnippet("project-brief-watershed-presence")),
      localSnippet(sourceSnippet("project-brief-watershed-presence-wiring")),
    ],
  },
];
