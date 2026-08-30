//// Pure tests for `tree.gleam`: path joining, breadcrumbs, deterministic
//// row ordering, and the two render rules that need no live channel — a
//// corrupt directory value, and a path a folder delete has covered. No
//// `Document`, no `SharedDirectory`, no `sluice` — every case here is a
//// plain-data assertion.

import gleam/json
import gleeunit/should
import watershed/handle
import watershed/json_ot.{Index, Key, VArray, VObject, VString}

import json_workspace_lustre/tree

// ── path joining and breadcrumbs ────────────────────────────────────────────

pub fn valid_tree_name_test() -> Nil {
  tree.valid_name("api") |> should.be_true()
  tree.valid_name(" api ") |> should.be_true()
}

pub fn invalid_tree_name_test() -> Nil {
  tree.valid_name("") |> should.be_false()
  tree.valid_name("   ") |> should.be_false()
  tree.valid_name("specs/api") |> should.be_false()
}

pub fn join_path_at_root_test() -> Nil {
  tree.join_path("/", "specs") |> should.equal("/specs")
}

pub fn join_path_nested_test() -> Nil {
  tree.join_path("/specs", "api") |> should.equal("/specs/api")
}

pub fn parent_path_of_root_is_root_test() -> Nil {
  tree.parent_path("/") |> should.equal("/")
}

pub fn parent_path_of_top_level_folder_test() -> Nil {
  tree.parent_path("/specs") |> should.equal("/")
}

pub fn parent_path_of_nested_folder_test() -> Nil {
  tree.parent_path("/specs/api") |> should.equal("/specs")
}

pub fn breadcrumbs_at_root_test() -> Nil {
  tree.breadcrumbs("/") |> should.equal([#("/", "/")])
}

pub fn breadcrumbs_nested_test() -> Nil {
  tree.breadcrumbs("/specs/api")
  |> should.equal([#("/", "/"), #("specs", "/specs"), #("api", "/specs/api")])
}

// ── row ordering ─────────────────────────────────────────────────────────────

pub fn rows_put_folders_before_documents_test() -> Nil {
  let document_handle = handle.encode_handle("doc-1")
  tree.rows("/", ["zeta"], [#("alpha", document_handle)])
  |> should.equal([
    tree.FolderRow("zeta", "/zeta"),
    tree.DocumentRow("alpha", "/alpha", corrupt: False),
  ])
}

pub fn rows_sort_each_block_alphabetically_test() -> Nil {
  let document_handle = handle.encode_handle("doc-1")
  tree.rows("/", ["b", "a"], [#("z", document_handle), #("m", document_handle)])
  |> should.equal([
    tree.FolderRow("a", "/a"),
    tree.FolderRow("b", "/b"),
    tree.DocumentRow("m", "/m", corrupt: False),
    tree.DocumentRow("z", "/z", corrupt: False),
  ])
}

pub fn rows_join_paths_under_the_current_folder_test() -> Nil {
  let document_handle = handle.encode_handle("doc-1")
  tree.rows("/specs", ["nested"], [#("api", document_handle)])
  |> should.equal([
    tree.FolderRow("nested", "/specs/nested"),
    tree.DocumentRow("api", "/specs/api", corrupt: False),
  ])
}

// ── corrupt values ───────────────────────────────────────────────────────────

pub fn a_non_handle_directory_value_is_marked_corrupt_test() -> Nil {
  tree.rows("/", [], [#("garbage", json.string("not a handle"))])
  |> should.equal([tree.DocumentRow("garbage", "/garbage", corrupt: True)])
}

pub fn a_handle_directory_value_is_not_corrupt_test() -> Nil {
  tree.rows("/", [], [#("config", handle.encode_handle("doc-9"))])
  |> should.equal([tree.DocumentRow("config", "/config", corrupt: False)])
}

// ── the deleted-folder banner rule ──────────────────────────────────────────

pub fn a_deleted_path_covers_itself_test() -> Nil {
  tree.path_covers("/specs", "/specs") |> should.be_true()
}

pub fn a_deleted_path_covers_a_descendant_test() -> Nil {
  tree.path_covers("/specs", "/specs/api") |> should.be_true()
}

pub fn a_deleted_path_does_not_cover_a_sibling_test() -> Nil {
  tree.path_covers("/specs", "/spec") |> should.be_false()
}

pub fn a_deleted_path_does_not_cover_an_unrelated_folder_test() -> Nil {
  tree.path_covers("/specs", "/notes") |> should.be_false()
}

pub fn deleting_the_root_covers_every_path_test() -> Nil {
  tree.path_covers("/", "/specs/api") |> should.be_true()
}

// ── JSON paths ───────────────────────────────────────────────────────────────

pub fn value_at_reads_object_and_array_paths_test() -> Nil {
  let value =
    VObject([
      #("a.b", VString("flat")),
      #("a", VObject([#("b", VArray([VString("nested")]))])),
    ])

  tree.value_at(value, [Key("a.b")]) |> should.equal(Ok(VString("flat")))
  tree.value_at(value, [Key("a"), Key("b"), Index(0)])
  |> should.equal(Ok(VString("nested")))
}

pub fn value_at_returns_none_for_a_stale_path_test() -> Nil {
  tree.value_at(VObject([]), [Key("missing")]) |> should.equal(Error(Nil))
  tree.value_at(VArray([VString("first")]), [Index(-1)])
  |> should.equal(Error(Nil))
}
