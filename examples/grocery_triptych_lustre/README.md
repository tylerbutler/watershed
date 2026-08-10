# grocery_triptych_lustre — one interaction, three set semantics

Add `"milk"` to all three sets, use the shared remove action, then add `"milk"`
again. The result is the whole demo:

- **GSet:** present
- **TwoPSet:** absent forever — the item is tombstoned
- **OrSet:** present again

This app keeps the experiment controlled: one typed document, three channels on
the same root map, one shared add input, one shared remove surface, and shared
scenario buttons. If the panels diverge, they diverge because the set kinds mean
different things, not because the UI drove them differently.

## Which kind to use

- **`GSet`** for irreversible monotonic facts: once true, always true.
- **`TwoPSet`** only when permanent removal is a real requirement.
- **`OrSet`** as the general default when remove-then-re-add must work.

`GSet` is also the only panel where remove is absent in the API itself: the
constraint is not a rejected call, it is that grow-only removal is not
expressible.

## What the scenarios prove

### Tombstone

The **Tombstone** button automates the headline sequence with fixed item
`"milk"`: add → shared remove → re-add. It is intentionally one-shot per room.
Once `TwoPSet` has crossed the remove phase, that room cannot honestly rerun the
scenario. Use a fresh room URL to reset.

### Concurrent add/remove

The **Concurrent add/remove** button uses two tabs and fixed item `"eggs"`.
One tab seeds the item, invites a second ready tab over a ripple, waits for an
acknowledgement, sends a targeted `go`, and only then performs the initiator's
shared remove while the peer performs the concurrent add.

The ripple is only for timing and peer selection. The durable state is still the
actual set operations on the three channels. Tests and smoke checks converge to:

- **GSet:** present
- **TwoPSet:** absent
- **OrSet:** present

That is the observed add-wins outcome for `OrSet`. It does **not** mean the
three channels move atomically; they are independent durable channels, and the UI
only batches nearby updates for display.

Both scenarios derive their disabled/complete state from the room's durable
snapshots, not from local tab memory. Reopening the same `?document=` URL keeps
the consumed state; a fresh URL creates a fresh room.

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
parameter. Reuse that full URL in another tab or browser to join the same room;
change or remove `?document=` for a fresh room.

## Checks

```sh
gleam test        # in-process convergence tests
pnpm run smoke    # live floodgate smoke: ready callbacks + room adoption + outcomes
```

> The demo mints an HS256 dev JWT in the browser using the server's dev secret.
> This is for local dev only; a real deployment issues tokens from a backend and
> never ships the tenant secret to the client.
