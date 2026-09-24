import gleam/json
import gleam/string
import startest/expect

import watershed/git_storage
import watershed/wire/fluid_summary

pub fn published_commit_history_decodes_test() -> Nil {
  let body =
    "[{
      \"sha\": \"commit-2\",
      \"commit\": {
        \"message\": \"watershed summary\",
        \"committer\": {\"date\": \"1720000000\"},
        \"tree\": {\"sha\": \"tree-2\"}
      },
      \"parents\": [{\"sha\": \"commit-1\"}]
    }]"

  json.parse(body, git_storage.versions_decoder())
  |> expect.to_equal(
    Ok([
      git_storage.SummaryVersion(
        id: "commit-2",
        tree_id: "tree-2",
        message: "watershed summary",
        created_at: "1720000000",
      ),
    ]),
  )
}

pub fn version_history_uses_historian_commits_url_test() -> Nil {
  git_storage.versions_url("http://127.0.0.1:3000", "default", "document-1", 10)
  |> expect.to_equal(
    "http://127.0.0.1:3000/repos/default/commits?sha=document-1&count=10",
  )
}

pub fn non_positive_version_count_is_invalid_test() -> Nil {
  git_storage.validate_version_count(0)
  |> expect.to_equal(Error(git_storage.InvalidVersionCount(0)))

  git_storage.validate_version_count(-1)
  |> expect.to_equal(Error(git_storage.InvalidVersionCount(-1)))
}

pub fn published_commit_resolves_its_tree_test() -> Nil {
  json.parse(
    "{\"tree\": {\"sha\": \"tree-2\"}}",
    git_storage.commit_tree_decoder(),
  )
  |> expect.to_equal(Ok("tree-2"))

  git_storage.commit_url("https://storage.example", "default", "commit-2")
  |> expect.to_equal(
    "https://storage.example/repos/default/git/commits/commit-2",
  )
}

pub fn shared_tree_storage_decodes_binary_and_utf8_blobs_test() -> Nil {
  git_storage.decode_hierarchy_blob(
    "/binary",
    "binary-id",
    "{\"content\":\"AP+A\",\"encoding\":\"base64\"}",
  )
  |> expect.to_equal(Ok(<<0, 255, 128>>))

  git_storage.decode_hierarchy_blob(
    "/text",
    "text-id",
    "{\"content\":\"héllo\",\"encoding\":\"utf-8\"}",
  )
  |> expect.to_equal(Ok(<<"héllo":utf8>>))

  git_storage.decode_hierarchy_blob(
    "/bad",
    "bad-id",
    "{\"content\":\"%%%\",\"encoding\":\"base64\"}",
  )
  |> expect.to_equal(
    Error(git_storage.HierarchyBlobUnreadable(
      "/bad",
      "bad-id",
      "the content is not base64",
    )),
  )

  git_storage.decode_hierarchy_blob(
    "/bad",
    "bad-id",
    "{\"content\":\"value\",\"encoding\":\"gzip\"}",
  )
  |> expect.to_equal(
    Error(git_storage.HierarchyBlobUnreadable(
      "/bad",
      "bad-id",
      "unsupported encoding: gzip",
    )),
  )
}

pub fn shared_tree_storage_decodes_component_names_and_kinds_test() -> Nil {
  git_storage.decode_hierarchy_tree(
    "/",
    "tree-id",
    "{\"tree\":[
      {\"path\":\"slash%2Fname\",\"sha\":\"blob-id\",\"type\":\"blob\",\"mode\":\"100644\"},
      {\"path\":\"水\",\"sha\":\"tree-id-2\",\"type\":\"tree\",\"mode\":\"040000\"}
    ]}",
  )
  |> expect.to_equal(
    Ok([
      git_storage.HierarchyTreeEntry(
        name: "slash/name",
        sha: "blob-id",
        kind: git_storage.HierarchyBlob,
      ),
      git_storage.HierarchyTreeEntry(
        name: "水",
        sha: "tree-id-2",
        kind: git_storage.HierarchyTree,
      ),
    ]),
  )

  git_storage.decode_hierarchy_tree(
    "/",
    "tree-id",
    "{\"tree\":[
      {\"path\":\"slash%2Fname\",\"sha\":\"one\",\"type\":\"blob\",\"mode\":\"100644\"},
      {\"path\":\"slash/name\",\"sha\":\"two\",\"type\":\"blob\",\"mode\":\"100644\"}
    ]}",
  )
  |> expect.to_equal(
    Error(
      git_storage.SummaryStructure(fluid_summary.MalformedEntry(
        "/",
        "duplicate entry: slash/name",
      )),
    ),
  )
}

pub fn shared_tree_storage_builds_upstream_git_bodies_test() -> Nil {
  git_storage.hierarchy_blob_body(<<0, 255, 128>>)
  |> expect.to_equal("{\"content\":\"AP+A\",\"encoding\":\"base64\"}")

  git_storage.hierarchy_tree_body([
    git_storage.HierarchyTreeEntry(
      name: "slash/name",
      sha: "blob-id",
      kind: git_storage.HierarchyBlob,
    ),
    git_storage.HierarchyTreeEntry(
      name: "水",
      sha: "tree-id",
      kind: git_storage.HierarchyTree,
    ),
    git_storage.HierarchyTreeEntry(
      name: "plus+cash$",
      sha: "plus-id",
      kind: git_storage.HierarchyBlob,
    ),
  ])
  |> expect.to_equal(
    "{\"tree\":[
      {\"mode\":\"100644\",\"path\":\"slash%2Fname\",\"sha\":\"blob-id\",\"type\":\"blob\"},
      {\"mode\":\"040000\",\"path\":\"%E6%B0%B4\",\"sha\":\"tree-id\",\"type\":\"tree\"},
      {\"mode\":\"100644\",\"path\":\"plus%2Bcash%24\",\"sha\":\"plus-id\",\"type\":\"blob\"}
    ]}"
    |> string.replace("\n", "")
    |> string.replace(" ", ""),
  )
}

pub fn shared_tree_storage_validates_complete_tree_before_upload_test() -> Nil {
  git_storage.validate_hierarchy(fluid_summary.SummaryBlob(<<>>))
  |> expect.to_equal(
    Error(
      git_storage.SummaryStructure(fluid_summary.WrongKind(
        "/",
        fluid_summary.TreeHandle,
      )),
    ),
  )

  git_storage.validate_hierarchy(
    fluid_summary.SummaryTree([
      #("copy", fluid_summary.SummaryHandle("/blob", fluid_summary.BlobHandle)),
    ]),
  )
  |> expect.to_equal(
    Error(
      git_storage.SummaryStructure(fluid_summary.UnsupportedEntry(
        "/copy",
        "hierarchy contains an unresolved handle",
      )),
    ),
  )

  git_storage.validate_hierarchy(
    fluid_summary.SummaryTree([
      #("same", fluid_summary.SummaryBlob(<<>>)),
      #("same", fluid_summary.SummaryTree([])),
    ]),
  )
  |> expect.to_equal(
    Error(
      git_storage.SummaryStructure(fluid_summary.MalformedEntry(
        "/",
        "duplicate entry: same",
      )),
    ),
  )
}
