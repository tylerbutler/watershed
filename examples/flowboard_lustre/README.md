# Flowboard

The complete Lustre application from the watershed build guide. It demonstrates
typed document bootstrap, optimistic local updates, remote subscriptions, a
shared counter, and ephemeral presence.

## Run it

Start a floodgate development server on port 4000 (`just integration-up`), then run:

```sh
pnpm install
pnpm build
pnpm serve
```

Open <http://localhost:8080> in two tabs. A local card move renders at once. The
other tab receives the remote edit through the same `SharedChanged` update path.
