import gleam/bit_array
import gleam/io
import gleam/json
import gleam/list
import watershed/git_storage
import watershed/wire/fluid_summary

@target(erlang)
import envoy

@target(javascript)
import envoy as javascript_envoy
@target(javascript)
import gleam/javascript/promise.{type Promise}

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
  let assert Ok(tenant) = envoy.get("WATERSHED_TREE_STORAGE_TENANT")
  let assert Ok(token) = envoy.get("WATERSHED_TREE_STORAGE_TOKEN")
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
