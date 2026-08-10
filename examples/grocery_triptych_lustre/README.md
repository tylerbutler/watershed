# grocery_triptych_lustre: one interaction, three set semantics

Add `"milk"` to all three sets, remove it with the shared action, then add it
again.

- **GSet:** present
- **TwoPSet:** absent forever. The item is tombstoned.
- **OrSet:** present again

The app uses one typed document, three channels on the same root map, one
shared add field, one shared remove control, and shared scenario buttons. If
the panels diverge, the set kinds caused it.

## Which kind to use

- **`GSet`** for irreversible monotonic facts: once true, always true.
- **`TwoPSet`** when removal must be permanent.
- **`OrSet`** when remove-then-re-add must work.

`GSet` is the only panel without `remove` in the API. The constraint is the
missing function, not a rejected call.

## What the scenarios prove

### Tombstone

The **Tombstone** button runs the headline sequence with fixed item `"milk"`:
add, shared remove, re-add. It is one-shot per room. Once `TwoPSet` crosses the
remove phase, that room cannot rerun the scenario honestly. Use a fresh room URL
to reset.

### Concurrent add/remove

The **Concurrent add/remove** button uses two tabs and fixed item `"eggs"`. One
tab seeds the item, invites a second ready tab over a ripple, waits for an
acknowledgement, sends a targeted `go`, and then performs the initiator's
shared remove while the peer adds concurrently.

The ripple handles timing and peer selection. The durable state comes from the
set operations on the three channels. Tests and smoke checks converge to:

- **GSet:** present
- **TwoPSet:** absent
- **OrSet:** present

That is the observed add-wins outcome for `OrSet`. It does not mean the three
channels move atomically; they are independent durable channels, and the UI only
batches nearby updates for display.

Both scenarios derive disabled and complete state from the room's durable
snapshots, not local tab memory. Reopening the same `?document=` URL keeps the
consumed state. A fresh URL creates a fresh room.

## Run it

From the repository root:

```sh
just integration-up   # floodgate dev server on :4000
```

From this directory:

```sh
pnpm install
pnpm run build
pnpm run serve        # http://localhost:8080
```

Loading the page without `?document=` creates a new room and adds the query
parameter. Reuse that full URL in another tab or browser to join the same room.
Change or remove `?document=` for a fresh room.

## Checks

```sh
gleam test        # in-process convergence tests
pnpm run smoke    # live floodgate smoke: ready callbacks + room adoption + outcomes
```

> The demo mints an HS256 dev JWT in the browser using the server's dev secret.
> This is for local dev only. A real deployment issues tokens from a backend and
> never ships the tenant secret to the client.
