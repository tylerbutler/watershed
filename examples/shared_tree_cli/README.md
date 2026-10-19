# SharedTree without an SDK seed

This CLI creates a persistent SharedTree container with Watershed, then opens
and edits it through the public JavaScript or BEAM facade. Its own
`shared_tree_cli.Note` schema has a required title and an optional note. It reads
no fixtures and imports no Fluid SDK code.

## Run

Use the pinned Floodgate service described in the
[oracle README](../../tools/shared-tree-oracle/README.md). This example uses
the plain-HTTP/Phoenix profile on both targets. Set the service address and
development credentials in your environment:

```sh
export WATERSHED_HOST=127.0.0.1
export WATERSHED_PORT=4000
export WATERSHED_TENANT='<your development tenant>'
export WATERSHED_SECRET='<your development tenant secret>'
```

For a local server, check out
[Floodgate](https://github.com/tylerbutler/floodgate) at
`0eb493fc46d1bb9baf1151a6ccdde93544e057e7`. From that checkout, start it in a
separate terminal with the same environment:

```sh
PORT="$WATERSHED_PORT" \
FLOODGATE_BIND="$WATERSHED_HOST" \
FLOODGATE_PUBLIC_URL="http://$WATERSHED_HOST:$WATERSHED_PORT" \
FLOODGATE_TENANT_ID="$WATERSHED_TENANT" \
FLOODGATE_JWT_SECRET="$WATERSHED_SECRET" \
FLOODGATE_STORAGE_BACKEND=shelf \
FLOODGATE_DATA_DIR=./shared-tree-cli-data \
gleam run
```

Install the repository's Node transport dependencies with `pnpm install` at
the repository root. They supply `ws`, `phoenix`, and the existing transport
helpers; the CLI needs no Fluid npm packages. Gleam resolves the CLI's declared
dependencies when you run it.

```sh
cd examples/shared_tree_cli
gleam run --target javascript -- create
# Keep the printed "document: <id>".
gleam run --target erlang -- open <id>
gleam run --target erlang -- set-title <id> "Edited on BEAM"
gleam run --target javascript -- open <id>
```

`create` prints the assigned ID before it tries to open the document. If opening
fails, keep that ID and use `open`; do not create a replacement. A lost creation
response can leave a created document whose ID you did not receive. Watershed
reports this uncertainty and does not retry the POST.

`set-title` waits for `is_synced`, with a bounded wait, before closing. The CLI
prints the typed root after loading or editing and exits nonzero on failure.
It does not wait a fixed delay and assume an edit reached the service.

Local token minting is for development only. Production applications should
obtain a tenant-write creation token from their service, then a
document-scoped token for the returned ID. Do not ship a tenant secret to a
browser.

## API flow

Pass `container.CreateConfig(base_url, tenant, token)`, `schema.configuration()`,
and a `Note` directly to `create_tree_container`. The API compiles the declaration
to supply both the stored schema and construction encoder. The JavaScript facade
returns a promise; the BEAM facade returns a result. Both preserve structured
creation and storage errors. Creation starts no WebSocket connection and does
not retry an uncertain result.

After `connect` reports readiness, call `open_tree(document, schema.configuration())`.
It checks the bootstrap map's `"tree"` binding and returns `tree.Tree(Note)`.
Capture the root with `tree.required_root`, update its `schema.title()`
property with `tree.set`, and read the ordinary Note with `tree.read_root`.
The same handle supports transactions, observation, and history.
This fixed layout uses datastore `A`, map `/A/root`, and tree `/A/_C`;
opening follows the checked binding rather than hardcoding that address.

## Checks

```sh
gleam test --target erlang
gleam test --target javascript
```
