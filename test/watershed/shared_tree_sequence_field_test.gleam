import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import startest/expect
import watershed/fluid_ids
import watershed/tree/array_fixture
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/sequence_field
import watershed/tree/sequence_field_fixture
import watershed/tree/types

const max_safe_integer = 9_007_199_254_740_991

const items_type = "org.watershed.shared-tree.m3.Items"

fn revision(suffix: String) -> fluid_ids.StableId {
  let assert Ok(id) =
    fluid_ids.stable_id("10000000-0000-4000-8000-0000000000" <> suffix)
  id
}

fn atom(revision: Option(fluid_ids.StableId), local_id: Int) -> types.AtomId {
  types.AtomId(revision, local_id)
}

fn no_child(_: types.AtomId) {
  Ok([])
}

pub fn shared_tree_sequence_editor_matches_upstream_test() {
  fixtures.assert_case(
    "sequence-field-editor",
    sequence_field_fixture.run_editor,
  )
}

pub fn shared_tree_sequence_rejects_zero_count_marks_test() {
  sequence_field.from_marks([
    sequence_field.Mark(0, None, sequence_field.Noop, None),
  ])
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_sequence_rejects_invalid_ranges_and_children_test() {
  let a = atom(None, 0)
  [
    sequence_field.Mark(-1, None, sequence_field.Noop, None),
    sequence_field.Mark(
      2,
      None,
      sequence_field.Attach(sequence_field.Insert(atom(None, max_safe_integer))),
      None,
    ),
    sequence_field.Mark(2, None, sequence_field.Noop, Some(a)),
    sequence_field.Mark(1, None, sequence_field.Rename(a), None),
  ]
  |> list.each(fn(mark) {
    sequence_field.from_marks([mark]) |> expect.to_be_error
  })
}

pub fn shared_tree_sequence_split_offsets_all_range_identities_test() {
  let a = revision("01")
  let b = revision("02")
  let c = revision("03")
  let d = revision("04")
  let e = revision("05")
  let f = revision("06")
  let mark =
    sequence_field.Mark(
      3,
      Some(atom(Some(a), 10)),
      sequence_field.AttachAndDetach(
        sequence_field.MoveIn(atom(Some(b), 20), Some(atom(Some(c), 30))),
        sequence_field.MoveOut(
          atom(Some(d), 40),
          Some(atom(Some(e), 50)),
          Some(atom(Some(f), 60)),
        ),
      ),
      None,
    )
  sequence_field.split_mark(mark, 1)
  |> expect.to_equal(
    Ok(#(
      sequence_field.Mark(
        1,
        Some(atom(Some(a), 10)),
        sequence_field.AttachAndDetach(
          sequence_field.MoveIn(atom(Some(b), 20), Some(atom(Some(c), 30))),
          sequence_field.MoveOut(
            atom(Some(d), 40),
            Some(atom(Some(e), 50)),
            Some(atom(Some(f), 60)),
          ),
        ),
        None,
      ),
      sequence_field.Mark(
        2,
        Some(atom(Some(a), 11)),
        sequence_field.AttachAndDetach(
          sequence_field.MoveIn(atom(Some(b), 21), Some(atom(Some(c), 31))),
          sequence_field.MoveOut(
            atom(Some(d), 41),
            Some(atom(Some(e), 51)),
            Some(atom(Some(f), 61)),
          ),
        ),
        None,
      ),
    )),
  )
  sequence_field.split_mark(mark, 0) |> expect.to_be_error
  sequence_field.split_mark(mark, 3) |> expect.to_be_error
  Nil
}

pub fn shared_tree_sequence_split_marks_rejoin_only_matching_ranges_test() {
  let a = revision("0a")
  let b = revision("0b")
  let c = revision("0c")
  let families = [
    sequence_field.Mark(2, Some(atom(Some(a), 0)), sequence_field.Noop, None),
    sequence_field.Mark(
      2,
      Some(atom(Some(a), 2)),
      sequence_field.Attach(sequence_field.Insert(atom(Some(b), 10))),
      None,
    ),
    sequence_field.Mark(
      2,
      Some(atom(Some(a), 4)),
      sequence_field.Attach(sequence_field.MoveIn(
        atom(Some(b), 20),
        Some(atom(Some(c), 30)),
      )),
      None,
    ),
    sequence_field.Mark(
      2,
      None,
      sequence_field.Detach(sequence_field.Remove(
        atom(Some(b), 40),
        Some(atom(Some(c), 50)),
      )),
      None,
    ),
    sequence_field.Mark(
      2,
      None,
      sequence_field.Detach(sequence_field.MoveOut(
        atom(Some(b), 60),
        Some(atom(Some(c), 70)),
        Some(atom(Some(a), 80)),
      )),
      None,
    ),
    sequence_field.Mark(
      2,
      Some(atom(Some(a), 6)),
      sequence_field.AttachAndDetach(
        sequence_field.Insert(atom(Some(b), 90)),
        sequence_field.Remove(atom(Some(c), 100), None),
      ),
      None,
    ),
    sequence_field.Mark(
      2,
      Some(atom(Some(a), 8)),
      sequence_field.Rename(atom(Some(c), 110)),
      None,
    ),
  ]
  families
  |> list.each(fn(mark) {
    let assert Ok(#(first, second)) = sequence_field.split_mark(mark, 1)
    let assert Ok(rejoined) = sequence_field.from_marks([first, second])
    sequence_field.to_marks(rejoined) |> expect.to_equal([mark])
  })

  let assert Ok(unmerged) =
    sequence_field.from_marks([
      sequence_field.Mark(1, Some(atom(Some(a), 0)), sequence_field.Noop, None),
      sequence_field.Mark(1, Some(atom(Some(b), 1)), sequence_field.Noop, None),
    ])
  sequence_field.to_marks(unmerged)
  |> expect.to_equal([
    sequence_field.Mark(1, Some(atom(Some(a), 0)), sequence_field.Noop, None),
    sequence_field.Mark(1, Some(atom(Some(b), 1)), sequence_field.Noop, None),
  ])
}

pub fn shared_tree_sequence_does_not_create_unsafe_merged_mark_test() {
  let first =
    sequence_field.Mark(
      max_safe_integer,
      Some(atom(None, 0)),
      sequence_field.Noop,
      None,
    )
  let second =
    sequence_field.Mark(
      1,
      Some(atom(None, max_safe_integer)),
      sequence_field.Noop,
      None,
    )
  let assert Ok(change) = sequence_field.from_marks([first, second])
  sequence_field.to_marks(change) |> expect.to_equal([first, second])
  sequence_field.into_delta(change, no_child)
  |> expect.to_equal(Ok(sequence_field.DeltaResult(None, [], [])))
}

pub fn shared_tree_sequence_editors_preserve_pre_edit_gaps_test() {
  let move_id = atom(Some(revision("07")), 11)
  let cell_id = atom(Some(revision("08")), 14)
  let assert Ok(before) = sequence_field.move(2, 2, 0, move_id, cell_id)
  sequence_field.to_marks(before)
  |> expect.to_equal([
    sequence_field.Mark(
      2,
      Some(cell_id),
      sequence_field.Attach(sequence_field.MoveIn(move_id, None)),
      None,
    ),
    sequence_field.Mark(2, None, sequence_field.Noop, None),
    sequence_field.Mark(
      2,
      None,
      sequence_field.Detach(sequence_field.MoveOut(move_id, None, None)),
      None,
    ),
  ])

  let assert Ok(after) = sequence_field.move(0, 2, 4, move_id, cell_id)
  sequence_field.to_marks(after)
  |> expect.to_equal([
    sequence_field.Mark(
      2,
      None,
      sequence_field.Detach(sequence_field.MoveOut(move_id, None, None)),
      None,
    ),
    sequence_field.Mark(2, None, sequence_field.Noop, None),
    sequence_field.Mark(
      2,
      Some(cell_id),
      sequence_field.Attach(sequence_field.MoveIn(move_id, None)),
      None,
    ),
  ])

  let assert Ok(interior) = sequence_field.move(0, 3, 1, move_id, cell_id)
  sequence_field.to_marks(interior)
  |> expect.to_equal([
    sequence_field.Mark(
      1,
      None,
      sequence_field.Detach(sequence_field.MoveOut(move_id, None, None)),
      None,
    ),
    sequence_field.Mark(
      3,
      Some(cell_id),
      sequence_field.Attach(sequence_field.MoveIn(move_id, None)),
      None,
    ),
    sequence_field.Mark(
      2,
      None,
      sequence_field.Detach(sequence_field.MoveOut(
        atom(Some(revision("07")), 12),
        None,
        None,
      )),
      None,
    ),
  ])
}

pub fn shared_tree_sequence_interior_move_preserves_nonzero_source_skip_test() {
  let move_id = atom(Some(revision("14")), 120)
  let cell_id = atom(Some(revision("15")), 130)
  let assert Ok(change) = sequence_field.move(2, 3, 3, move_id, cell_id)
  sequence_field.to_marks(change)
  |> expect.to_equal([
    sequence_field.Mark(2, None, sequence_field.Noop, None),
    sequence_field.Mark(
      1,
      None,
      sequence_field.Detach(sequence_field.MoveOut(move_id, None, None)),
      None,
    ),
    sequence_field.Mark(
      3,
      Some(cell_id),
      sequence_field.Attach(sequence_field.MoveIn(move_id, None)),
      None,
    ),
    sequence_field.Mark(
      2,
      None,
      sequence_field.Detach(sequence_field.MoveOut(
        atom(Some(revision("14")), 121),
        None,
        None,
      )),
      None,
    ),
  ])
}

pub fn shared_tree_sequence_editors_validate_before_suppressing_empty_test() {
  let id = atom(None, 0)
  let unsafe = atom(None, max_safe_integer + 1)
  let assert Ok(empty_insert) = sequence_field.insert(0, 0, id, None)
  let assert Ok(empty_remove) = sequence_field.remove(0, 0, id)
  let assert Ok(empty_move) = sequence_field.move(0, 0, 0, id, id)
  sequence_field.to_marks(empty_insert) |> expect.to_equal([])
  sequence_field.to_marks(empty_remove) |> expect.to_equal([])
  sequence_field.to_marks(empty_move) |> expect.to_equal([])
  sequence_field.insert(-1, 0, id, None) |> expect.to_be_error
  sequence_field.remove(0, 0, unsafe) |> expect.to_be_error
  sequence_field.move(0, 0, max_safe_integer + 1, id, id)
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_sequence_validates_input_and_output_lengths_separately_test() {
  let id = atom(None, 0)
  let cell = atom(None, 10)
  sequence_field.move(max_safe_integer - 1, 1, 0, id, cell)
  |> expect.to_be_ok
  sequence_field.move(0, 1, max_safe_integer, id, cell)
  |> expect.to_be_ok
  sequence_field.insert(max_safe_integer, 1, cell, None)
  |> expect.to_be_error
  sequence_field.remove(max_safe_integer, 1, id)
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_sequence_builds_ordered_child_changes_test() {
  let first = atom(None, 20)
  let second = atom(None, 21)
  let assert Ok(change) =
    sequence_field.build_child_changes([#(1, first), #(4, second)])
  sequence_field.to_marks(change)
  |> expect.to_equal([
    sequence_field.Mark(1, None, sequence_field.Noop, None),
    sequence_field.Mark(1, None, sequence_field.Noop, Some(first)),
    sequence_field.Mark(2, None, sequence_field.Noop, None),
    sequence_field.Mark(1, None, sequence_field.Noop, Some(second)),
  ])
  sequence_field.build_child_changes([#(1, first), #(1, second)])
  |> expect.to_be_error
  sequence_field.build_child_changes([#(-1, first)]) |> expect.to_be_error
  Nil
}

pub fn shared_tree_sequence_into_delta_covers_effect_families_test() {
  let a = atom(None, 1)
  let b = atom(None, 10)
  let c = atom(None, 20)
  let child = atom(None, 30)
  let nested = [#("x", forest.FieldDelta([forest.Mark(1, None, None, [])]))]
  let callback = fn(id) {
    case id == child {
      True -> Ok(nested)
      False -> Error(types.CorruptData("test", "unexpected child"))
    }
  }
  let assert Ok(change) =
    sequence_field.from_marks([
      sequence_field.Mark(1, None, sequence_field.Noop, Some(child)),
      sequence_field.Mark(
        1,
        Some(a),
        sequence_field.Attach(sequence_field.Insert(b)),
        Some(child),
      ),
      sequence_field.Mark(
        1,
        None,
        sequence_field.Detach(sequence_field.Remove(b, Some(c))),
        None,
      ),
      sequence_field.Mark(
        1,
        Some(a),
        sequence_field.Detach(sequence_field.MoveOut(b, Some(c), None)),
        None,
      ),
      sequence_field.Mark(
        1,
        Some(a),
        sequence_field.Attach(sequence_field.MoveIn(b, Some(c))),
        None,
      ),
      sequence_field.Mark(
        1,
        Some(a),
        sequence_field.AttachAndDetach(
          sequence_field.Insert(b),
          sequence_field.Remove(c, None),
        ),
        None,
      ),
      sequence_field.Mark(1, Some(a), sequence_field.Rename(c), None),
    ])
  sequence_field.into_delta(change, callback)
  |> expect.to_equal(
    Ok(
      sequence_field.DeltaResult(
        Some(
          forest.FieldDelta([
            forest.Mark(1, None, None, nested),
            forest.Mark(1, Some(a), None, []),
            forest.Mark(1, None, Some(c), []),
            forest.Mark(1, Some(c), None, []),
          ]),
        ),
        [
          forest.DetachedChange(a, nested),
        ],
        [
          forest.Rename(a, b, 1),
          forest.Rename(a, c, 1),
        ],
      ),
    ),
  )
}

pub fn shared_tree_sequence_into_delta_propagates_child_error_test() {
  let child = atom(None, 30)
  let assert Ok(change) = sequence_field.build_child_changes([#(0, child)])
  sequence_field.into_delta(change, fn(_) {
    Error(types.CorruptData("child", "failed"))
  })
  |> expect.to_equal(Error(types.CorruptData("child", "failed")))
}

pub fn shared_tree_sequence_into_delta_handles_detached_children_and_renames_test() {
  let a = atom(None, 1)
  let b = atom(None, 2)
  let c = atom(None, 3)
  let child = atom(None, 4)
  let fields = [
    #("nested", forest.FieldDelta([forest.Mark(2, None, None, [])])),
  ]
  let assert Ok(change) =
    sequence_field.from_marks([
      sequence_field.Mark(1, Some(a), sequence_field.Noop, Some(child)),
      sequence_field.Mark(
        1,
        Some(a),
        sequence_field.Detach(sequence_field.Remove(a, None)),
        Some(child),
      ),
      sequence_field.Mark(
        1,
        Some(a),
        sequence_field.AttachAndDetach(
          sequence_field.MoveIn(b, Some(c)),
          sequence_field.MoveOut(b, None, None),
        ),
        None,
      ),
      sequence_field.Mark(1, Some(a), sequence_field.Rename(c), None),
    ])
  sequence_field.into_delta(change, fn(id) {
    case id == child {
      True -> Ok(fields)
      False -> Error(types.CorruptData("test", "unexpected child"))
    }
  })
  |> expect.to_equal(
    Ok(
      sequence_field.DeltaResult(
        None,
        [
          forest.DetachedChange(a, fields),
          forest.DetachedChange(a, fields),
        ],
        [],
      ),
    ),
  )
}

pub fn shared_tree_sequence_into_delta_routes_empty_cell_children_first_test() {
  let a = atom(None, 1)
  let b = atom(None, 2)
  let c = atom(None, 3)
  let d = atom(None, 4)
  let child = atom(None, 5)
  let fields = [
    #("nested", forest.FieldDelta([forest.Mark(2, None, None, [])])),
  ]
  let assert Ok(change) =
    sequence_field.from_marks([
      sequence_field.Mark(
        1,
        Some(a),
        sequence_field.AttachAndDetach(
          sequence_field.MoveIn(b, Some(c)),
          sequence_field.Remove(d, None),
        ),
        Some(child),
      ),
      sequence_field.Mark(
        1,
        Some(a),
        sequence_field.Detach(sequence_field.MoveOut(b, None, None)),
        Some(child),
      ),
    ])
  sequence_field.into_delta(change, fn(_) { Ok(fields) })
  |> expect.to_equal(
    Ok(
      sequence_field.DeltaResult(
        None,
        [
          forest.DetachedChange(a, fields),
          forest.DetachedChange(a, fields),
        ],
        [
          forest.Rename(c, d, 1),
          forest.Rename(a, b, 1),
        ],
      ),
    ),
  )
}

pub fn shared_tree_sequence_allows_populated_insert_with_child_change_test() {
  let insert_id = atom(Some(revision("16")), 140)
  let child = atom(None, 141)
  let fields = [
    #("nested", forest.FieldDelta([forest.Mark(1, None, None, [])])),
  ]
  let assert Ok(change) =
    sequence_field.from_marks([
      sequence_field.Mark(
        1,
        None,
        sequence_field.Attach(sequence_field.Insert(insert_id)),
        Some(child),
      ),
    ])
  sequence_field.into_delta(change, fn(_) { Ok(fields) })
  |> expect.to_equal(
    Ok(
      sequence_field.DeltaResult(
        Some(
          forest.FieldDelta([
            forest.Mark(1, None, None, fields),
          ]),
        ),
        [],
        [],
      ),
    ),
  )
}

pub fn shared_tree_sequence_delta_applies_counted_move_to_forest_test() {
  let assert Ok(initial) =
    forest.new(
      array_fixture.view_id(),
      array_fixture.stored("rootArray"),
      Some(
        types.ArrayValue(items_type, [
          types.StringValue("A"),
          types.StringValue("B"),
          types.StringValue("C"),
          types.StringValue("D"),
        ]),
      ),
    )
  let move_id = atom(None, 40)
  let cell_id = atom(Some(revision("09")), 50)
  let assert Ok(change) = sequence_field.move(0, 2, 4, move_id, cell_id)
  let assert Ok(parts) = sequence_field.into_delta(change, no_child)
  let assert Some(local) = parts.local
  let assert Ok(delta) =
    forest.delta(
      forest.DeltaData(
        None,
        [
          #(
            "rootFieldKey",
            forest.FieldDelta([
              forest.Mark(1, None, None, [#("", local)]),
            ]),
          ),
        ],
        [],
        [],
        parts.global,
        parts.rename,
        [],
      ),
    )
  let assert Ok(moved) = forest.apply_delta(initial, delta)
  forest.array_values(moved, [])
  |> expect.to_equal(
    Ok([
      types.StringValue("C"),
      types.StringValue("D"),
      types.StringValue("A"),
      types.StringValue("B"),
    ]),
  )
}

pub fn shared_tree_sequence_deltas_apply_insert_remove_and_interior_move_test() {
  let assert Ok(inserted) =
    apply_root_change(
      ["A", "B"],
      sequence_field.insert(
        1,
        2,
        atom(Some(revision("0d")), 60),
        Some(revision("0e")),
      ),
      [
        forest.Build(atom(Some(revision("0d")), 60), [
          types.StringValue("X"),
          types.StringValue("Y"),
        ]),
      ],
    )
  forest.array_values(inserted, [])
  |> expect.to_equal(
    Ok([
      types.StringValue("A"),
      types.StringValue("X"),
      types.StringValue("Y"),
      types.StringValue("B"),
    ]),
  )

  let removed_id = atom(Some(revision("0f")), 70)
  let assert Ok(removed) =
    apply_root_change(
      ["A", "B", "C", "D"],
      sequence_field.remove(1, 2, removed_id),
      [],
    )
  forest.array_values(removed, [])
  |> expect.to_equal(
    Ok([
      types.StringValue("A"),
      types.StringValue("D"),
    ]),
  )
  let assert Ok(removed_reference) = forest.locate_detached(removed, removed_id)
  forest.read_node(removed, removed_reference)
  |> expect.to_equal(Ok(types.StringValue("B")))

  let assert Ok(interior) =
    apply_root_change(
      ["A", "B", "C", "D"],
      sequence_field.move(
        0,
        3,
        1,
        atom(Some(revision("10")), 80),
        atom(Some(revision("11")), 90),
      ),
      [],
    )
  forest.array_values(interior, [])
  |> expect.to_equal(
    Ok([
      types.StringValue("A"),
      types.StringValue("B"),
      types.StringValue("C"),
      types.StringValue("D"),
    ]),
  )
}

pub fn shared_tree_sequence_paired_endpoints_apply_across_fields_test() {
  let root =
    types.ObjectValue("org.watershed.shared-tree.m3.Root", [
      #(
        "left",
        types.ArrayValue(items_type, [
          types.StringValue("A"),
          types.StringValue("B"),
        ]),
      ),
      #("right", types.ArrayValue(items_type, [types.StringValue("C")])),
      #("byKey", types.MapValue("org.watershed.shared-tree.m3.ArrayMap", [])),
      #("narrow", types.ArrayValue("org.watershed.shared-tree.m3.Points", [])),
    ])
  let assert Ok(initial) =
    forest.new(
      array_fixture.view_id(),
      array_fixture.stored("objectArrays"),
      Some(root),
    )
  let move_id = atom(Some(revision("12")), 100)
  let assert Ok(out) = sequence_field.move_out(0, 2, move_id)
  let assert Ok(into) =
    sequence_field.move_in(1, 2, move_id, atom(Some(revision("13")), 110))
  let assert Ok(out_delta) = sequence_field.into_delta(out, no_child)
  let assert Ok(in_delta) = sequence_field.into_delta(into, no_child)
  let assert Some(out_local) = out_delta.local
  let assert Some(in_local) = in_delta.local
  let assert Ok(delta) =
    forest.delta(
      forest.DeltaData(
        None,
        [
          #(
            "rootFieldKey",
            forest.FieldDelta([
              forest.Mark(1, None, None, [
                #(
                  "left",
                  forest.FieldDelta([
                    forest.Mark(1, None, None, [#("", out_local)]),
                  ]),
                ),
                #(
                  "right",
                  forest.FieldDelta([
                    forest.Mark(1, None, None, [#("", in_local)]),
                  ]),
                ),
              ]),
            ]),
          ),
        ],
        [],
        [],
        list.append(out_delta.global, in_delta.global),
        list.append(out_delta.rename, in_delta.rename),
        [],
      ),
    )
  let assert Ok(moved) = forest.apply_delta(initial, delta)
  forest.array_values(moved, ["left"]) |> expect.to_equal(Ok([]))
  forest.array_values(moved, ["right"])
  |> expect.to_equal(
    Ok([
      types.StringValue("C"),
      types.StringValue("A"),
      types.StringValue("B"),
    ]),
  )
}

fn apply_root_change(
  values: List(String),
  change: Result(sequence_field.Changeset, types.TreeError),
  builds: List(forest.Build),
) -> Result(forest.Forest, types.TreeError) {
  use initial <- result.try(forest.new(
    array_fixture.view_id(),
    array_fixture.stored("rootArray"),
    Some(types.ArrayValue(items_type, list.map(values, types.StringValue))),
  ))
  use change <- result.try(change)
  use parts <- result.try(sequence_field.into_delta(change, no_child))
  let assert Some(local) = parts.local
  use delta <- result.try(
    forest.delta(
      forest.DeltaData(
        None,
        [
          #(
            "rootFieldKey",
            forest.FieldDelta([
              forest.Mark(1, None, None, [#("", local)]),
            ]),
          ),
        ],
        builds,
        [],
        parts.global,
        parts.rename,
        [],
      ),
    ),
  )
  forest.apply_delta(initial, delta)
}
