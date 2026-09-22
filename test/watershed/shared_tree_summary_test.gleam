import gleam/dict
import gleam/json
import gleam/option.{None, Some}
import startest/expect
import watershed/tree/fixtures
import watershed/tree/summary_fixture
import watershed/wire/fluid_summary

fn array(values: List(json.Json)) -> json.Json {
  json.array(values, fn(value) { value })
}

fn summary_fixture_input(bytes: String) -> json.Json {
  json.object([
    #(
      "previousSnapshot",
      json.object([
        #(
          "version",
          json.object([
            #("id", json.string("root")),
            #("treeId", json.string("root")),
          ]),
        ),
        #(
          "tree",
          json.object([
            #("id", json.string("root")),
            #("blobs", json.object([])),
            #("trees", json.object([])),
          ]),
        ),
        #("blobs", json.object([])),
        #("blobEncoding", json.string("base64")),
      ]),
    ),
    #(
      "scenarios",
      array([
        json.object([
          #("label", json.string("snapshot-entries")),
        ]),
        json.object([
          #("label", json.string("emitted-entries")),
          #(
            "summary",
            array([
              json.object([
                #("name", json.string("binary")),
                #("kind", json.string("blob")),
                #("bytes", json.string(bytes)),
              ]),
            ]),
          ),
        ]),
      ]),
    ),
  ])
}

pub fn shared_tree_summary_resolves_binary_blob_from_previous_test() -> Nil {
  let previous =
    fluid_summary.SummaryTree([
      #("binary", fluid_summary.SummaryBlob(<<0, 255, 128>>)),
    ])

  fluid_summary.resolve(
    fluid_summary.SummaryTree([
      #(
        "copy",
        fluid_summary.SummaryHandle("/binary", fluid_summary.BlobHandle),
      ),
    ]),
    Some(previous),
  )
  |> expect.to_equal(
    Ok(
      fluid_summary.SummaryTree([
        #("copy", fluid_summary.SummaryBlob(<<0, 255, 128>>)),
      ]),
    ),
  )
}

pub fn shared_tree_summary_reports_missing_and_wrong_references_test() -> Nil {
  let previous =
    fluid_summary.SummaryTree([
      #("blob", fluid_summary.SummaryBlob(<<1>>)),
      #("tree", fluid_summary.SummaryTree([])),
    ])

  fluid_summary.resolve(
    fluid_summary.SummaryHandle("/blob", fluid_summary.BlobHandle),
    None,
  )
  |> expect.to_equal(Error(fluid_summary.MissingEntry("/blob")))

  fluid_summary.resolve(
    fluid_summary.SummaryHandle("/missing", fluid_summary.BlobHandle),
    Some(previous),
  )
  |> expect.to_equal(Error(fluid_summary.MissingEntry("/missing")))

  fluid_summary.resolve(
    fluid_summary.SummaryHandle("/tree", fluid_summary.BlobHandle),
    Some(previous),
  )
  |> expect.to_equal(
    Error(fluid_summary.WrongKind("/tree", fluid_summary.BlobHandle)),
  )
}

pub fn shared_tree_summary_allows_repeated_references_and_rejects_cycles_test() -> Nil {
  let previous =
    fluid_summary.SummaryTree([
      #("blob", fluid_summary.SummaryBlob(<<7>>)),
      #("self", fluid_summary.SummaryHandle("/self", fluid_summary.BlobHandle)),
      #("left", fluid_summary.SummaryHandle("/right", fluid_summary.BlobHandle)),
      #("right", fluid_summary.SummaryHandle("/left", fluid_summary.BlobHandle)),
    ])

  fluid_summary.resolve(
    fluid_summary.SummaryTree([
      #("first", fluid_summary.SummaryHandle("/blob", fluid_summary.BlobHandle)),
      #(
        "second",
        fluid_summary.SummaryHandle("/blob", fluid_summary.BlobHandle),
      ),
    ]),
    Some(previous),
  )
  |> expect.to_equal(
    Ok(
      fluid_summary.SummaryTree([
        #("first", fluid_summary.SummaryBlob(<<7>>)),
        #("second", fluid_summary.SummaryBlob(<<7>>)),
      ]),
    ),
  )

  fluid_summary.resolve(
    fluid_summary.SummaryHandle("/self", fluid_summary.BlobHandle),
    Some(previous),
  )
  |> expect.to_equal(Error(fluid_summary.CyclicReference("/self")))

  fluid_summary.resolve(
    fluid_summary.SummaryHandle("/left", fluid_summary.BlobHandle),
    Some(previous),
  )
  |> expect.to_equal(Error(fluid_summary.CyclicReference("/left")))
}

pub fn shared_tree_summary_validates_names_paths_and_root_handles_test() -> Nil {
  fluid_summary.encode_component("plus+cash$")
  |> expect.to_equal("plus%2Bcash%24")

  fluid_summary.resolve(
    fluid_summary.SummaryTree([
      #("same", fluid_summary.SummaryBlob(<<>>)),
      #("same", fluid_summary.SummaryTree([])),
    ]),
    None,
  )
  |> expect.to_equal(
    Error(fluid_summary.MalformedEntry("/", "duplicate entry: same")),
  )

  fluid_summary.resolve(
    fluid_summary.SummaryHandle("/bad%ZZ", fluid_summary.BlobHandle),
    Some(fluid_summary.SummaryTree([])),
  )
  |> expect.to_equal(
    Error(fluid_summary.MalformedEntry("/bad%ZZ", "invalid percent encoding")),
  )

  let previous =
    fluid_summary.SummaryTree([
      #("slash/name", fluid_summary.SummaryBlob(<<2>>)),
      #("plus+cash$", fluid_summary.SummaryBlob(<<3>>)),
    ])
  fluid_summary.resolve(
    fluid_summary.SummaryHandle("/slash%2Fname", fluid_summary.BlobHandle),
    Some(previous),
  )
  |> expect.to_equal(Ok(fluid_summary.SummaryBlob(<<2>>)))

  fluid_summary.resolve(
    fluid_summary.SummaryHandle("/plus%2Bcash%24", fluid_summary.BlobHandle),
    Some(previous),
  )
  |> expect.to_equal(Ok(fluid_summary.SummaryBlob(<<3>>)))

  fluid_summary.resolve(
    fluid_summary.SummaryHandle("", fluid_summary.TreeHandle),
    Some(previous),
  )
  |> expect.to_equal(Ok(previous))

  fluid_summary.resolve(
    fluid_summary.SummaryHandle("/", fluid_summary.TreeHandle),
    Some(previous),
  )
  |> expect.to_equal(Error(fluid_summary.MissingEntry("/")))

  fluid_summary.resolve(
    fluid_summary.SummaryHandle(
      "0123456789abcdef0123456789abcdef01234567",
      fluid_summary.TreeHandle,
    ),
    Some(previous),
  )
  |> expect.to_equal(
    Error(fluid_summary.MissingEntry("0123456789abcdef0123456789abcdef01234567")),
  )
}

pub fn shared_tree_summary_materializes_snapshot_bytes_and_paths_test() -> Nil {
  let tree =
    json.object([
      #("id", json.string("root-tree")),
      #(
        "blobs",
        json.object([
          #("binary", json.string("binary-id")),
          #("empty", json.string("empty-id")),
        ]),
      ),
      #(
        "trees",
        json.object([
          #(
            "slash/name",
            json.object([
              #("id", json.string("child-tree")),
              #("blobs", json.object([#("text", json.string("text-id"))])),
              #("trees", json.object([])),
              #("commits", json.object([])),
            ]),
          ),
        ]),
      ),
      #("commits", json.object([])),
    ])
  let blobs =
    dict.from_list([
      #("binary-id", <<0, 255, 128>>),
      #("empty-id", <<>>),
      #("text-id", <<"héllo":utf8>>),
    ])

  fluid_summary.from_snapshot(tree, blobs)
  |> expect.to_equal(
    Ok(
      fluid_summary.SummaryTree([
        #("binary", fluid_summary.SummaryBlob(<<0, 255, 128>>)),
        #("empty", fluid_summary.SummaryBlob(<<>>)),
        #(
          "slash/name",
          fluid_summary.SummaryTree([
            #("text", fluid_summary.SummaryBlob(<<"héllo":utf8>>)),
          ]),
        ),
      ]),
    ),
  )
}

pub fn shared_tree_summary_refuses_incomplete_or_legacy_snapshots_test() -> Nil {
  let missing_blob =
    json.object([
      #("id", json.string("root-tree")),
      #("blobs", json.object([#("binary", json.string("missing-id"))])),
      #("trees", json.object([])),
      #("commits", json.object([])),
    ])
  fluid_summary.from_snapshot(missing_blob, dict.new())
  |> expect.to_equal(
    Error(fluid_summary.MissingEntry("/binary (snapshot blob missing-id)")),
  )

  let legacy_commit =
    json.object([
      #("id", json.string("root-tree")),
      #("blobs", json.object([])),
      #("trees", json.object([])),
      #("commits", json.object([#("legacy", json.string("commit-id"))])),
    ])
  fluid_summary.from_snapshot(legacy_commit, dict.new())
  |> expect.to_equal(
    Error(fluid_summary.UnsupportedEntry(
      "/legacy",
      "snapshot commits are not supported",
    )),
  )
}

pub fn shared_tree_summary_accepts_omitted_empty_commit_map_test() -> Nil {
  let tree =
    json.object([
      #("id", json.string("root-tree")),
      #("blobs", json.object([])),
      #("trees", json.object([])),
    ])

  fluid_summary.from_snapshot(tree, dict.new())
  |> expect.to_equal(Ok(fluid_summary.SummaryTree([])))
}

pub fn shared_tree_summary_fixture_uses_only_replay_input_test() -> Nil {
  let assert Ok(first) = summary_fixture.run(summary_fixture_input("AP+A"))
  let assert Ok(second) = summary_fixture.run(summary_fixture_input("AQID"))
  fixtures.first_difference(first, second) |> expect.to_be_error

  let _ =
    summary_fixture.run(summary_fixture_input("%%%"))
    |> expect.to_be_error
  Nil
}
