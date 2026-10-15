import gleam/bit_array
import gleam/dict
@target(erlang)
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import signet/types as token
import spillway/message
import spillway/types
import watershed/git_storage
@target(javascript)
import watershed/runtime
@target(erlang)
import watershed/runtime_beam
import watershed/runtime_core
import watershed/sluice/frame
@target(javascript)
import watershed/transport_js
import watershed/tree/compression_fixture
import watershed/tree/types as tree_types
import watershed/wire/fluid_summary

@target(erlang)
import envoy
@target(erlang)
import gleam/erlang/process

@target(javascript)
import envoy as javascript_envoy
@target(javascript)
import gleam/javascript/promise.{type Promise}

fn connect_message(token_value: String) -> message.ConnectMessage {
  message.ConnectMessage(
    tenant_id: "tenant",
    document_id: "compressed",
    token: Some(token_value),
    client: types.Client(
      mode: types.WriteMode,
      details: types.ClientDetails(
        capabilities: types.ClientCapabilities(interactive: True),
        client_type: None,
        environment: None,
        device: None,
      ),
      permission: [],
      user: token.User("storage-probe", dict.new()),
      scopes: ["doc:read", "doc:write"],
      timestamp: None,
    ),
    versions: ["^0.1.0"],
    driver_version: None,
    mode: types.WriteMode,
    nonce: None,
    epoch: None,
    supported_features: None,
    relay_user_agent: None,
  )
}

fn expected_tree() -> fluid_summary.SummaryEntry {
  fluid_summary.SummaryTree([
    #("binary", fluid_summary.SummaryBlob(<<0, 255, 128>>)),
    #("empty", fluid_summary.SummaryBlob(<<>>)),
    #("empty-tree", fluid_summary.SummaryTree([])),
    #("plus+cash$", fluid_summary.SummaryBlob(<<43>>)),
    #("repeat", fluid_summary.SummaryBlob(<<0, 255, 128>>)),
    #(
      "slash/name",
      fluid_summary.SummaryTree([
        #("水", fluid_summary.SummaryBlob(<<"héllo":utf8>>)),
      ]),
    ),
  ])
}

fn replay_seed() -> #(runtime_core.BootstrapSeed, String) {
  let assert Ok(#(seed, _, address)) =
    compression_fixture.actor_seed_case("partial-summary-prefix-tail")
  #(seed, address)
}

@target(erlang)
fn check_actor_http_replay(
  host: String,
  port: Int,
  token_value: String,
) -> Nil {
  let #(seed, address) = replay_seed()
  let callbacks_subject = process.new_subject()
  let assert Ok(actor) =
    runtime_beam.start_with_transport_and_seed(
      host: host,
      port: port,
      connect_message: connect_message(token_value),
      seed: seed,
      transport: runtime_beam.Transport(connect: fn(callbacks) {
        process.send(callbacks_subject, callbacks)
      }),
    )
  let assert Ok(callbacks) = process.receive(callbacks_subject, 1000)
  callbacks.on_ready(
    runtime_beam.TransportHandle(
      push: fn(_, _) { Ok(Nil) },
      close: fn() { Nil },
      drop: fn() { Nil },
    ),
  )
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "storage-reader",
      tenant_id: "tenant",
      document_id: "compressed",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 204,
      initial_clients: ["storage-reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    ),
  )
  runtime_beam.await_ready(actor) |> assert_ok
  runtime_beam.tree_read(actor, address, ["label"])
  |> assert_replayed_label
  process.send(actor, runtime_beam.Shutdown)
}

fn assert_ok(value: Result(Nil, String)) -> Nil {
  let assert Ok(Nil) = value
  Nil
}

fn assert_replayed_label(
  value: Result(Option(tree_types.TreeValue), String),
) -> Nil {
  let assert Ok(Some(tree_types.StringValue(label))) = value
  label |> string.length |> expect_equal(309_336)
  expect_equal(label == "compression-baseline", False)
}

fn expect_equal(value: value, expected: value) -> Nil {
  let assert True = value == expected
  Nil
}

@target(javascript)
fn await_js_ready(
  ready: transport_js.Cell(Option(Result(Nil, String))),
  attempts: Int,
) -> Promise(Result(Nil, String)) {
  case transport_js.get_cell(ready), attempts {
    Some(outcome), _ -> promise.resolve(outcome)
    None, 0 -> promise.resolve(Error("actor HTTP replay timed out"))
    None, _ -> {
      use _ <- promise.await(promise.wait(10))
      await_js_ready(ready, attempts - 1)
    }
  }
}

@target(javascript)
fn check_actor_http_replay(
  base_url: String,
  token_value: String,
) -> Promise(Nil) {
  let #(seed, address) = replay_seed()
  let callbacks = transport_js.new_cell(None)
  let ready = transport_js.new_cell(None)
  let actor =
    runtime.start_with_transport_and_seed(
      http_base_url: base_url,
      connect_message: connect_message(token_value),
      seed: seed,
      transport: runtime.Transport(connect: fn(handlers) {
        transport_js.set_cell(callbacks, Some(handlers))
        runtime.TransportHandle(
          push: fn(_, _) { Nil },
          close: fn() { Nil },
          drop: fn() { Nil },
          hold: fn() { Nil },
          resume: fn() { Nil },
        )
      }),
      on_ready: fn(outcome) { transport_js.set_cell(ready, Some(outcome)) },
    )
  let assert Some(callbacks) = transport_js.get_cell(callbacks)
  callbacks.on_event(
    "connect_document_success",
    frame.encode_connected(
      client_id: "storage-reader",
      tenant_id: "tenant",
      document_id: "compressed",
      scopes: ["doc:read", "doc:write"],
      checkpoint_sequence_number: 204,
      initial_clients: ["storage-reader"],
      initial_messages: [],
      timestamp: 0,
      presence_v1: False,
    )
      |> json.to_string,
  )
  use outcome <- promise.await(await_js_ready(ready, 100))
  assert_ok(outcome)
  runtime.tree_read(actor, address, ["label"])
  |> assert_replayed_label
  runtime.close(actor)
  promise.resolve(Nil)
}

fn failing_tree() -> fluid_summary.SummaryEntry {
  fluid_summary.SummaryTree([
    #("uploaded-first", fluid_summary.SummaryBlob(<<1, 2, 3>>)),
    #(
      "fail-after-upload",
      fluid_summary.SummaryTree([
        #("nested", fluid_summary.SummaryBlob(<<4, 5, 6>>)),
      ]),
    ),
  ])
}

fn invalid_tree() -> fluid_summary.SummaryEntry {
  fluid_summary.SummaryTree([
    #("copy", fluid_summary.SummaryHandle("/binary", fluid_summary.BlobHandle)),
  ])
}

fn observation(root: String, tree: fluid_summary.SummaryEntry) -> String {
  json.object([
    #("root", json.string(root)),
    #("entries", json.array(flatten(tree, []), fn(value) { value })),
  ])
  |> json.to_string
}

fn captured_observation(
  root: String,
  tree: fluid_summary.SummaryEntry,
) -> String {
  json.object([
    #("root", json.string(root)),
    #(
      "entries",
      json.array(
        [
          json.object([
            #("components", json.array([], json.string)),
            #("kind", json.string("tree")),
          ]),
          ..flatten(tree, [])
        ],
        fn(value) { value },
      ),
    ),
  ])
  |> json.to_string
}

fn flatten(
  entry: fluid_summary.SummaryEntry,
  components: List(String),
) -> List(json.Json) {
  case entry {
    fluid_summary.SummaryBlob(bytes) -> [
      json.object([
        #("components", json.array(components, json.string)),
        #("kind", json.string("blob")),
        #("bytes", json.string(bit_array.base64_encode(bytes, True))),
      ]),
    ]
    fluid_summary.SummaryTree(entries) ->
      entries
      |> list.flat_map(fn(item) {
        let path = list.append(components, [item.0])
        let self = case item.1 {
          fluid_summary.SummaryTree(_) -> [
            json.object([
              #("components", json.array(path, json.string)),
              #("kind", json.string("tree")),
            ]),
          ]
          _ -> []
        }
        list.append(self, flatten(item.1, path))
      })
    fluid_summary.SummaryHandle(_, _) -> []
  }
}

fn check_fetch_failures(
  missing_commit: Result(fluid_summary.SummaryEntry, git_storage.StorageError),
  forbidden: Result(fluid_summary.SummaryEntry, git_storage.StorageError),
  server_error: Result(fluid_summary.SummaryEntry, git_storage.StorageError),
  malformed_commit: Result(fluid_summary.SummaryEntry, git_storage.StorageError),
  malformed_tree: Result(fluid_summary.SummaryEntry, git_storage.StorageError),
  malformed_blob: Result(fluid_summary.SummaryEntry, git_storage.StorageError),
  invalid_encoding: Result(fluid_summary.SummaryEntry, git_storage.StorageError),
  invalid_base64: Result(fluid_summary.SummaryEntry, git_storage.StorageError),
  missing_descendant: Result(
    fluid_summary.SummaryEntry,
    git_storage.StorageError,
  ),
  cycle: Result(fluid_summary.SummaryEntry, git_storage.StorageError),
) -> Nil {
  let assert Error(git_storage.UnexpectedStatus(_, 404, _)) = missing_commit
  let assert Error(git_storage.UnexpectedStatus(_, 403, _)) = forbidden
  let assert Error(git_storage.UnexpectedStatus(_, 500, _)) = server_error
  let assert Error(git_storage.ResponseDecodeFailed(_, _)) = malformed_commit
  let assert Error(git_storage.SummaryStructure(fluid_summary.MalformedEntry(
    _,
    _,
  ))) = malformed_tree
  let assert Error(git_storage.HierarchyBlobUnreadable(
    "/malformed-blob",
    "malformed-blob",
    _,
  )) = malformed_blob
  let assert Error(git_storage.HierarchyBlobUnreadable(
    "/bad-encoding",
    "bad-encoding-blob",
    "unsupported encoding: gzip",
  )) = invalid_encoding
  let assert Error(git_storage.HierarchyBlobUnreadable(
    "/bad-base64",
    "bad-base64-blob",
    "the content is not base64",
  )) = invalid_base64
  let assert Error(git_storage.HierarchyObjectMissing(
    "/missing",
    "missing-blob",
    git_storage.HierarchyBlob,
  )) = missing_descendant
  let assert Error(git_storage.SummaryStructure(fluid_summary.CyclicReference(
    "/loop",
  ))) = cycle
  Nil
}

fn check_stage_failures(
  invalid: Result(String, git_storage.StorageError),
  failed: Result(String, git_storage.StorageError),
) -> Nil {
  let assert Error(git_storage.SummaryStructure(fluid_summary.UnsupportedEntry(
    "/copy",
    _,
  ))) = invalid
  let assert Error(git_storage.UnexpectedStatus(_, 500, _)) = failed
  Nil
}

@target(erlang)
pub fn main() -> Nil {
  let assert Ok(base_url) = envoy.get("WATERSHED_TREE_STORAGE_URL")
  let assert Ok(host) = envoy.get("WATERSHED_TREE_STORAGE_HOST")
  let assert Ok(port_text) = envoy.get("WATERSHED_TREE_STORAGE_PORT")
  let assert Ok(port) = int.parse(port_text)
  let assert Ok(tenant) = envoy.get("WATERSHED_TREE_STORAGE_TENANT")
  let assert Ok(token) = envoy.get("WATERSHED_TREE_STORAGE_TOKEN")
  check_actor_http_replay(host, port, token)
  let assert Ok([compressed]) =
    git_storage.fetch_enveloped_deltas(
      base_url,
      tenant,
      token,
      "compressed",
      0,
      1,
    )
  let assert Some("lz4") = compressed.compression
  let assert Ok(fetched) =
    git_storage.fetch_hierarchy(base_url, tenant, token, "success-commit")
  let assert True = fetched == expected_tree()
  let assert Ok(root) =
    git_storage.stage_hierarchy(base_url, tenant, token, fetched)
  let assert Ok(staged) =
    git_storage.fetch_hierarchy(base_url, tenant, token, "staged-commit")
  let assert True = staged == fetched

  check_fetch_failures(
    git_storage.fetch_hierarchy(base_url, tenant, token, "missing-commit"),
    git_storage.fetch_hierarchy(base_url, tenant, token, "forbidden-commit"),
    git_storage.fetch_hierarchy(base_url, tenant, token, "error-commit"),
    git_storage.fetch_hierarchy(base_url, tenant, token, "malformed-commit"),
    git_storage.fetch_hierarchy(
      base_url,
      tenant,
      token,
      "malformed-tree-commit",
    ),
    git_storage.fetch_hierarchy(
      base_url,
      tenant,
      token,
      "malformed-blob-commit",
    ),
    git_storage.fetch_hierarchy(
      base_url,
      tenant,
      token,
      "invalid-encoding-commit",
    ),
    git_storage.fetch_hierarchy(
      base_url,
      tenant,
      token,
      "invalid-base64-commit",
    ),
    git_storage.fetch_hierarchy(
      base_url,
      tenant,
      token,
      "missing-descendant-commit",
    ),
    git_storage.fetch_hierarchy(base_url, tenant, token, "cycle-commit"),
  )
  check_stage_failures(
    git_storage.stage_hierarchy(base_url, tenant, token, invalid_tree()),
    git_storage.stage_hierarchy(base_url, tenant, token, failing_tree()),
  )
  let assert Ok(captured) =
    git_storage.fetch_hierarchy(base_url, tenant, token, "captured-commit")
  let assert Ok(captured_root) =
    git_storage.stage_hierarchy(base_url, tenant, token, captured)
  let assert Ok(captured_staged) =
    git_storage.fetch_hierarchy(
      base_url,
      tenant,
      token,
      "captured-staged-commit",
    )
  let assert True = captured_staged == captured
  io.println("WATERSHED_TREE_STORAGE=" <> observation(root, staged))
  io.println(
    "WATERSHED_TREE_STORAGE_CAPTURED="
    <> captured_observation(captured_root, captured_staged),
  )
}

@target(javascript)
pub fn main() -> Promise(Nil) {
  let assert Ok(base_url) = javascript_envoy.get("WATERSHED_TREE_STORAGE_URL")
  let assert Ok(tenant) = javascript_envoy.get("WATERSHED_TREE_STORAGE_TENANT")
  let assert Ok(token) = javascript_envoy.get("WATERSHED_TREE_STORAGE_TOKEN")
  use _ <- promise.await(check_actor_http_replay(base_url, token))
  use compressed_result <- promise.await(git_storage.fetch_enveloped_deltas(
    base_url,
    tenant,
    token,
    "compressed",
    0,
    1,
  ))
  let assert Ok([compressed]) = compressed_result
  let assert Some("lz4") = compressed.compression
  use fetched_result <- promise.await(git_storage.fetch_hierarchy(
    base_url,
    tenant,
    token,
    "success-commit",
  ))
  let assert Ok(fetched) = fetched_result
  let assert True = fetched == expected_tree()
  use staged_result <- promise.await(git_storage.stage_hierarchy(
    base_url,
    tenant,
    token,
    fetched,
  ))
  let assert Ok(root) = staged_result
  use refetched_result <- promise.await(git_storage.fetch_hierarchy(
    base_url,
    tenant,
    token,
    "staged-commit",
  ))
  let assert Ok(staged) = refetched_result
  let assert True = staged == fetched

  use missing_commit <- promise.await(git_storage.fetch_hierarchy(
    base_url,
    tenant,
    token,
    "missing-commit",
  ))
  use forbidden <- promise.await(git_storage.fetch_hierarchy(
    base_url,
    tenant,
    token,
    "forbidden-commit",
  ))
  use server_error <- promise.await(git_storage.fetch_hierarchy(
    base_url,
    tenant,
    token,
    "error-commit",
  ))
  use malformed_commit <- promise.await(git_storage.fetch_hierarchy(
    base_url,
    tenant,
    token,
    "malformed-commit",
  ))
  use malformed_tree <- promise.await(git_storage.fetch_hierarchy(
    base_url,
    tenant,
    token,
    "malformed-tree-commit",
  ))
  use malformed_blob <- promise.await(git_storage.fetch_hierarchy(
    base_url,
    tenant,
    token,
    "malformed-blob-commit",
  ))
  use invalid_encoding <- promise.await(git_storage.fetch_hierarchy(
    base_url,
    tenant,
    token,
    "invalid-encoding-commit",
  ))
  use invalid_base64 <- promise.await(git_storage.fetch_hierarchy(
    base_url,
    tenant,
    token,
    "invalid-base64-commit",
  ))
  use missing_descendant <- promise.await(git_storage.fetch_hierarchy(
    base_url,
    tenant,
    token,
    "missing-descendant-commit",
  ))
  use cycle <- promise.await(git_storage.fetch_hierarchy(
    base_url,
    tenant,
    token,
    "cycle-commit",
  ))
  check_fetch_failures(
    missing_commit,
    forbidden,
    server_error,
    malformed_commit,
    malformed_tree,
    malformed_blob,
    invalid_encoding,
    invalid_base64,
    missing_descendant,
    cycle,
  )
  use invalid <- promise.await(git_storage.stage_hierarchy(
    base_url,
    tenant,
    token,
    invalid_tree(),
  ))
  use failed <- promise.await(git_storage.stage_hierarchy(
    base_url,
    tenant,
    token,
    failing_tree(),
  ))
  check_stage_failures(invalid, failed)
  use captured_result <- promise.await(git_storage.fetch_hierarchy(
    base_url,
    tenant,
    token,
    "captured-commit",
  ))
  let assert Ok(captured) = captured_result
  use captured_stage_result <- promise.await(git_storage.stage_hierarchy(
    base_url,
    tenant,
    token,
    captured,
  ))
  let assert Ok(captured_root) = captured_stage_result
  use captured_refetch_result <- promise.await(git_storage.fetch_hierarchy(
    base_url,
    tenant,
    token,
    "captured-staged-commit",
  ))
  let assert Ok(captured_staged) = captured_refetch_result
  let assert True = captured_staged == captured
  io.println("WATERSHED_TREE_STORAGE=" <> observation(root, staged))
  io.println(
    "WATERSHED_TREE_STORAGE_CAPTURED="
    <> captured_observation(captured_root, captured_staged),
  )
  promise.resolve(Nil)
}
