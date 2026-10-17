# SharedTree item counter

The Fluid website's [simple SharedTree example](https://fluidframework.com/docs/start/examples),
rebuilt in Gleam and Lustre. Both versions store an array of strings, display
its length, insert an empty string at the start, and remove the first entry.
Removing from an empty array does nothing.

The [side-by-side source comparison](https://watershed.tylerbutler.com/sharedtree/item-counter)
walks through the schema, lifecycle, subscriptions, and edits. This app uses
watershed's **SharedTree** API, not its typed-map schema layer.
One `Tree(List(String))` supports reads, observation, and array edits, without
raw `TreeValue` adapters.
The [schema declaration](../../docs/shared-tree-schema-authoring.md) derives
the stored schema, view schema, and `List(String)` snapshot codec from one
typed array descriptor.

## Run

Start the development service from the repository root:

```sh
just integration-up
```

Then build and serve:

```sh
cd examples/shared_tree_item_counter_lustre
pnpm install
pnpm run build
pnpm run serve
```

Open <http://127.0.0.1:8080>. Wait for the URL to gain a `document` parameter,
then copy the **full URL** to another tab. Insert or remove in either tab.
Reload after the other tab receives an edit to see the saved state.
**Close** unsubscribes and closes that tab's document; reload to open it again.
Close does not promise to save edits that have not reached the service.

The server reuses the checklist example's HTTP proxy to avoid development CORS
issues. The Phoenix socket connects to Floodgate on port 4000. Development
tenant and secret query parameters follow the checklist example's conventions.

## What is being compared

The official source is pinned in [`upstream/`](upstream/README.md) with its MIT
license. It is a reference snapshot, not another runnable app in this package.
Use the upstream project to run the Fluid version.

The data model and user actions match; container setup does not. Fluid creates
a detached container, initializes a view, and attaches it. This app creates a
native container with its schema and empty root, then connects and opens the
tree. The schema namespace and container layouts are different. These apps
are **not** presented as opening each other's documents.

This is not a numeric counter DDS: two concurrent removals can target the
same entry. It counts the entries that survive the array's merge rules.

## Development authentication only

This app mints tokens in the browser using the local development tenant
secret. Do not deploy that authentication flow. Production apps must obtain
creation and document tokens from a backend.

No offline-authoring, reconnect durability, transactions, undo, schema
upgrades, or cross-SDK interoperability claims are made by this example.
Errors are visible; creation is never retried automatically because a lost
response can leave a created document whose ID was not received.

## Checks

```sh
gleam test --target javascript
```

With Floodgate running, from the repository root:

```sh
just shared-tree-item-counter
```

The browser gate requires Chromium and checks two isolated clients, empty
removal, edits from both clients, convergence, delivered-state reload, and
close. Set `WATERSHED_CHROME` if browser discovery needs an explicit path.
