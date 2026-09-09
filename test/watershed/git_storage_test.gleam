import gleam/json
import startest/expect

import watershed/git_storage

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

pub fn missing_commit_falls_back_to_legacy_tree_id_test() -> Nil {
  git_storage.resolve_summary_tree_id(
    "legacy-tree",
    Error(git_storage.UnexpectedStatus("commit-url", 404, "not found")),
  )
  |> expect.to_equal(Ok("legacy-tree"))
}

pub fn non_missing_commit_error_does_not_fall_back_test() -> Nil {
  let forbidden = git_storage.UnexpectedStatus("commit-url", 403, "forbidden")
  git_storage.resolve_summary_tree_id("legacy-tree", Error(forbidden))
  |> expect.to_equal(Error(forbidden))

  let malformed = git_storage.ResponseDecodeFailed("commit-url", "bad tree")
  git_storage.resolve_summary_tree_id("legacy-tree", Error(malformed))
  |> expect.to_equal(Error(malformed))
}
