# Incident board starter

The restrictions below apply to evaluated-agent submissions. Benchmark
maintainers may update the supplied scaffolding and acceptance tooling.

Read `task.md` for requirements. Implement `src/incident_eval/model.gleam` and
`src/incident_eval/schema.gleam`. You may add tests. Do not change the domain,
UI, build files, dependencies, SDK, or grading assets.

Use native Watershed SharedTree. Preserve the exported model functions and
native inspection accessors. The native accessors must return the actual tree
and document used by your model, not reconstructed diagnostics.

`init` receives native service URLs, development credentials, an optional
document ID, and a client ID. Return Lustre effects for asynchronous work.
`update` handles your internal messages; `apply` handles typed user actions.
The shell renders `read()` and maps model effects into its message loop.
The shell handles DOM events, ID generation, and URL updates.

Create only when no document ID was supplied. Observe local and remote changes.
Close must release subscriptions, the tree view, and the document, including
resources that arrive after Close. Use the supplied development service and
credentials only for local development.

```sh
pnpm check
pnpm build
```
