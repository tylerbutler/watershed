# Incident board starter

The restrictions below apply to evaluated-agent submissions. Benchmark
maintainers may update the supplied scaffolding and acceptance tooling.

Read `task.md` for requirements. Implement `src/model.ts` and `src/schema.ts`.
You may add tests under `test/`. Keep implementation changes in those two
model/schema files. Do not change the domain, UI, build files, dependencies, SDK,
or grading assets.

Use native Fluid SharedTree. Export the root schema as `BoardNode` and preserve
`start`, `nativeView`, and `nativeContainer`. The native accessors must return
the actual objects used by your session, not reconstructed diagnostics.

`start` receives a local-service endpoint, an optional document ID, and a client
ID. Create/attach only when no document ID was supplied. The shell subscribes
to the session and renders `read()`; emit an update after local and remote
changes and connection changes. `close()` must be idempotent and must release
resources. The shell handles DOM events and URL updates.

```sh
pnpm check
pnpm build
```

The service and authentication are for local development only. Use the supplied
local service with the SDK's local-mode client and development token provider.
Do not invent a production authentication flow.
