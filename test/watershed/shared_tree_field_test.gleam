import gleam/list
import gleam/option.{type Option, None, Some}
import startest/expect
import watershed/fluid_ids
import watershed/tree/forest
import watershed/tree/optional_field
import watershed/tree/schema
import watershed/tree/types.{type AtomId, AtomId, CorruptData, NumberValue}

fn revision(value: String) -> fluid_ids.StableId {
  let assert Ok(id) = fluid_ids.stable_id(value)
  id
}

fn atom(local_id: Int) -> AtomId {
  AtomId(Some(revision("00000000-0000-4000-8000-0000000000a0")), local_id)
}

fn atom_b(local_id: Int) -> AtomId {
  AtomId(Some(revision("00000000-0000-4000-8000-0000000000b0")), local_id)
}

pub fn shared_tree_field_clear_keeps_absence_distinct_from_active_test() {
  let id = AtomId(None, 1)
  optional_field.clear(True, id)
  |> expect.to_equal(optional_field.FieldChange(
    [],
    [],
    Some(optional_field.Replacement(True, None, id)),
  ))
  optional_field.set(True, AtomId(None, 0), id)
  |> expect.to_equal(optional_field.FieldChange(
    [],
    [],
    Some(optional_field.Replacement(
      True,
      Some(optional_field.Detached(AtomId(None, 0))),
      id,
    )),
  ))
}

pub fn shared_tree_field_validation_rejects_invalid_identities_test() {
  let high = AtomId(None, 9_007_199_254_740_991)
  [
    optional_field.FieldChange([#(AtomId(None, -1), atom(1))], [], None),
    optional_field.FieldChange([#(high, atom(1)), #(high, atom(2))], [], None),
    optional_field.FieldChange([#(atom(1), high), #(atom(2), high)], [], None),
    optional_field.FieldChange(
      [],
      [
        #(optional_field.Active, atom(1)),
        #(optional_field.Active, atom(2)),
      ],
      None,
    ),
  ]
  |> list.each(fn(change) {
    let assert Error(CorruptData(_, _)) = optional_field.validate(change)
    Nil
  })
}

pub fn shared_tree_field_validation_accepts_noop_and_cycle_test() {
  optional_field.FieldChange(
    [#(atom(1), atom(2)), #(atom(2), atom(1))],
    [],
    Some(optional_field.Replacement(False, Some(optional_field.Active), atom(3))),
  )
  |> optional_field.validate
  |> expect.to_equal(Ok(Nil))
}

pub fn shared_tree_field_compose_register_replacements_test() {
  let first = optional_field.set(True, atom(0), atom(1))
  let second = optional_field.set(False, atom_b(2), atom_b(3))
  let assert Ok(#(forward, [])) =
    optional_field.compose(first, second, [], fn(left, right, calls) {
      let assert Some(id) = left |> option.or(right)
      Ok(#(id, [#(left, right), ..calls]))
    })
  forward
  |> expect.to_equal(optional_field.FieldChange(
    [#(atom(0), atom_b(3))],
    [],
    Some(optional_field.Replacement(
      True,
      Some(optional_field.Detached(atom_b(2))),
      atom(1),
    )),
  ))

  let clear = optional_field.clear(False, atom(6))
  let assert Ok(#(set_then_clear, [])) =
    optional_field.compose(second, clear, [], fn(left, right, calls) {
      let assert Some(id) = left |> option.or(right)
      Ok(#(id, [#(left, right), ..calls]))
    })
  set_then_clear
  |> expect.to_equal(optional_field.FieldChange(
    [#(atom_b(2), atom(6))],
    [],
    Some(optional_field.Replacement(False, None, atom_b(3))),
  ))

  let assert Ok(#(clear_then_set, [])) =
    optional_field.compose(clear, second, [], fn(left, right, calls) {
      let assert Some(id) = left |> option.or(right)
      Ok(#(id, [#(left, right), ..calls]))
    })
  clear_then_set
  |> expect.to_equal(optional_field.FieldChange(
    [],
    [],
    Some(optional_field.Replacement(
      False,
      Some(optional_field.Detached(atom_b(2))),
      atom(6),
    )),
  ))
}

pub fn shared_tree_field_compose_maps_and_combines_child_changes_test() {
  let first =
    optional_field.FieldChange(
      [],
      [#(optional_field.Active, atom(40))],
      Some(optional_field.Replacement(False, None, atom(9))),
    )
  let second =
    optional_field.FieldChange(
      [],
      [#(optional_field.Detached(atom(9)), atom_b(41))],
      None,
    )
  let output = atom_b(45)
  let assert Ok(#(change, calls)) =
    optional_field.compose(first, second, [], fn(left, right, calls) {
      Ok(#(output, [#(left, right), ..calls]))
    })
  calls |> expect.to_equal([#(Some(atom(40)), Some(atom_b(41)))])
  change
  |> expect.to_equal(optional_field.FieldChange(
    [],
    [#(optional_field.Active, output)],
    Some(optional_field.Replacement(False, None, atom(9))),
  ))
}

pub fn shared_tree_field_compose_callback_refusal_returns_no_state_test() {
  let first =
    optional_field.FieldChange([], [#(optional_field.Active, atom(40))], None)
  optional_field.compose(first, first, ["unchanged"], fn(_, _, _) {
    Error(CorruptData("child", "callback refused"))
  })
  |> expect.to_equal(Error(CorruptData("child", "callback refused")))
}

pub fn shared_tree_field_callbacks_follow_register_map_order_test() {
  let interleaved = [
    #(optional_field.Detached(atom(4)), atom(40)),
    #(optional_field.Detached(atom(5)), atom(41)),
    #(optional_field.Detached(atom_b(4)), atom_b(42)),
  ]
  let change = optional_field.FieldChange([], interleaved, None)
  let empty = optional_field.FieldChange([], [], None)
  let assert Ok(#(composed, compose_calls)) =
    optional_field.compose(empty, change, [], fn(_, second, calls) {
      let assert Some(child) = second
      let output = atom_b(100 + list.length(calls))
      Ok(#(output, [child, ..calls]))
    })
  list.reverse(compose_calls)
  |> expect.to_equal([atom(40), atom_b(42), atom(41)])
  composed
  |> expect.to_equal(optional_field.FieldChange(
    [],
    [
      #(optional_field.Detached(atom(4)), atom_b(100)),
      #(optional_field.Detached(atom_b(4)), atom_b(101)),
      #(optional_field.Detached(atom(5)), atom_b(102)),
    ],
    None,
  ))

  let assert Ok(#(rebased, rebase_calls)) =
    optional_field.rebase(empty, change, [], fn(_, over, _, calls) {
      let assert Some(child) = over
      let output = atom_b(100 + list.length(calls))
      Ok(#(Some(output), [child, ..calls]))
    })
  list.reverse(rebase_calls)
  |> expect.to_equal([atom(40), atom_b(42), atom(41)])
  rebased
  |> expect.to_equal(composed)

  let authored =
    optional_field.FieldChange(
      [],
      [#(optional_field.Detached(atom(4)), atom(50))],
      None,
    )
  let assert Ok(#(_, compose_overlap_calls)) =
    optional_field.compose(authored, change, [], fn(first, second, calls) {
      let assert Some(child) = first |> option.or(second)
      Ok(#(child, [#(first, second), ..calls]))
    })
  list.reverse(compose_overlap_calls)
  |> expect.to_equal([
    #(Some(atom(50)), Some(atom(40))),
    #(None, Some(atom_b(42))),
    #(None, Some(atom(41))),
  ])

  let assert Ok(#(_, rebase_overlap_calls)) =
    optional_field.rebase(authored, change, [], fn(first, second, _, calls) {
      Ok(#(first |> option.or(second), [#(first, second), ..calls]))
    })
  list.reverse(rebase_overlap_calls)
  |> expect.to_equal([
    #(Some(atom(50)), Some(atom(40))),
    #(None, Some(atom_b(42))),
    #(None, Some(atom(41))),
  ])
}

pub fn shared_tree_field_invert_distinguishes_rollback_and_undo_test() {
  let inverse = Some(revision("00000000-0000-4000-8000-0000000000c0"))
  let change =
    optional_field.FieldChange(
      [],
      [
        #(optional_field.Active, atom(40)),
        #(optional_field.Detached(atom_b(2)), atom(41)),
      ],
      Some(optional_field.Replacement(
        False,
        Some(optional_field.Detached(atom_b(2))),
        atom_b(3),
      )),
    )
  optional_field.invert(change, True, inverse, 20)
  |> expect.to_equal(
    Ok(#(
      optional_field.FieldChange(
        [],
        [
          #(optional_field.Detached(atom_b(3)), atom(40)),
          #(optional_field.Active, atom(41)),
        ],
        Some(optional_field.Replacement(
          False,
          Some(optional_field.Detached(atom_b(3))),
          atom_b(2),
        )),
      ),
      20,
    )),
  )
  optional_field.invert(change, False, inverse, 20)
  |> expect.to_equal(
    Ok(#(
      optional_field.FieldChange(
        [],
        [
          #(optional_field.Detached(atom_b(3)), atom(40)),
          #(optional_field.Active, atom(41)),
        ],
        Some(optional_field.Replacement(
          False,
          Some(optional_field.Detached(atom_b(3))),
          AtomId(inverse, 21),
        )),
      ),
      21,
    )),
  )
}

pub fn shared_tree_field_invert_handles_clear_and_active_noop_test() {
  let inverse = Some(revision("00000000-0000-4000-8000-0000000000c0"))
  let clear = optional_field.clear(False, atom(6))
  optional_field.invert(clear, True, inverse, -1)
  |> expect.to_equal(
    Ok(#(
      optional_field.FieldChange(
        [],
        [],
        Some(optional_field.Replacement(
          True,
          Some(optional_field.Detached(atom(6))),
          AtomId(inverse, 0),
        )),
      ),
      0,
    )),
  )
  let noop =
    optional_field.FieldChange(
      [],
      [],
      Some(optional_field.Replacement(
        False,
        Some(optional_field.Active),
        atom(8),
      )),
    )
  optional_field.invert(noop, True, inverse, 20)
  |> expect.to_equal(Ok(#(optional_field.FieldChange([], [], None), 20)))
  optional_field.invert(noop, False, inverse, 20)
  |> expect.to_equal(
    Ok(#(
      optional_field.FieldChange(
        [],
        [],
        Some(optional_field.Replacement(
          False,
          Some(optional_field.Active),
          AtomId(inverse, 21),
        )),
      ),
      21,
    )),
  )
}

pub fn shared_tree_field_invert_allocator_bounds_are_atomic_test() {
  let clear = optional_field.clear(False, atom(6))
  let max = 9_007_199_254_740_991
  let assert Error(CorruptData(_, _)) =
    optional_field.invert(clear, False, None, -2)
  let assert Error(CorruptData(_, _)) =
    optional_field.invert(clear, False, None, max)
  Nil
}

pub fn shared_tree_field_rebase_maps_authored_and_base_children_test() {
  let authored =
    optional_field.FieldChange([], [#(optional_field.Active, atom_b(43))], None)
  let clear = optional_field.clear(False, atom(6))
  let assert Ok(#(rebased, calls)) =
    optional_field.rebase(
      authored,
      clear,
      [],
      fn(change, over, attach_state, calls) {
        let assert Some(id) = change |> option.or(over)
        Ok(#(Some(id), [#(change, over, attach_state), ..calls]))
      },
    )
  calls
  |> expect.to_equal([
    #(Some(atom_b(43)), None, optional_field.DetachedNode),
  ])
  rebased
  |> expect.to_equal(optional_field.FieldChange(
    [],
    [#(optional_field.Detached(atom(6)), atom_b(43))],
    None,
  ))

  let base =
    optional_field.FieldChange(
      [],
      [#(optional_field.Active, atom(42))],
      Some(optional_field.Replacement(False, None, atom(10))),
    )
  let assert Ok(#(base_only, base_calls)) =
    optional_field.rebase(
      optional_field.FieldChange([], [], None),
      base,
      [],
      fn(change, over, attach_state, calls) {
        let assert Some(id) = change |> option.or(over)
        Ok(#(Some(id), [#(change, over, attach_state), ..calls]))
      },
    )
  base_calls
  |> expect.to_equal([
    #(None, Some(atom(42)), optional_field.DetachedNode),
  ])
  base_only
  |> expect.to_equal(optional_field.FieldChange(
    [],
    [#(optional_field.Detached(atom(10)), atom(42))],
    None,
  ))
}

pub fn shared_tree_field_rebase_keeps_swap_algebra_legal_test() {
  let swap =
    optional_field.FieldChange(
      [#(atom(4), atom(5)), #(atom(5), atom(4))],
      [],
      None,
    )
  let change =
    optional_field.FieldChange(
      [#(atom(4), atom(9))],
      [
        #(optional_field.Detached(atom(4)), atom(40)),
        #(optional_field.Detached(atom(5)), atom(41)),
      ],
      None,
    )
  let assert Ok(#(rebased, states)) =
    optional_field.rebase(
      change,
      swap,
      [],
      fn(current, over, attach_state, states) {
        let assert Some(id) = current |> option.or(over)
        Ok(#(Some(id), [attach_state, ..states]))
      },
    )
  states
  |> expect.to_equal([
    optional_field.DetachedNode,
    optional_field.DetachedNode,
  ])
  rebased
  |> expect.to_equal(optional_field.FieldChange(
    [#(atom(4), atom(5))],
    [
      #(optional_field.Detached(atom(5)), atom(40)),
      #(optional_field.Detached(atom(4)), atom(41)),
    ],
    None,
  ))
}

pub fn shared_tree_field_rebase_callback_can_drop_or_refuse_test() {
  let child =
    optional_field.FieldChange([], [#(optional_field.Active, atom(40))], None)
  optional_field.rebase(child, child, Nil, fn(_, _, _, state) {
    Ok(#(None, state))
  })
  |> expect.to_equal(Ok(#(optional_field.FieldChange([], [], None), Nil)))
  optional_field.rebase(child, child, "unchanged", fn(_, _, _, _) {
    Error(CorruptData("child", "callback refused"))
  })
  |> expect.to_equal(Error(CorruptData("child", "callback refused")))
}

pub fn shared_tree_field_replace_revisions_visits_all_atom_positions_test() {
  let change =
    optional_field.FieldChange(
      [#(atom(1), atom_b(2))],
      [#(optional_field.Detached(atom(3)), atom_b(4))],
      Some(optional_field.Replacement(
        False,
        Some(optional_field.Detached(atom_b(5))),
        atom(6),
      )),
    )
  let replacement_revision =
    Some(revision("00000000-0000-4000-8000-0000000000d0"))
  optional_field.replace_revisions(change, fn(id) {
    Ok(AtomId(replacement_revision, id.local_id))
  })
  |> expect.to_equal(
    Ok(optional_field.FieldChange(
      [
        #(AtomId(replacement_revision, 1), AtomId(replacement_revision, 2)),
      ],
      [
        #(
          optional_field.Detached(AtomId(replacement_revision, 3)),
          AtomId(replacement_revision, 4),
        ),
      ],
      Some(optional_field.Replacement(
        False,
        Some(optional_field.Detached(AtomId(replacement_revision, 5))),
        AtomId(replacement_revision, 6),
      )),
    )),
  )
}

pub fn shared_tree_field_replace_revisions_rejects_callback_collisions_test() {
  let change =
    optional_field.FieldChange(
      [#(atom(1), atom(2)), #(atom(3), atom(4))],
      [],
      None,
    )
  let assert Error(CorruptData(_, _)) =
    optional_field.replace_revisions(change, fn(_) { Ok(atom(9)) })
  optional_field.replace_revisions(change, fn(_) {
    Error(CorruptData("revision", "callback refused"))
  })
  |> expect.to_equal(Error(CorruptData("revision", "callback refused")))
}

pub fn shared_tree_field_into_delta_keeps_local_global_and_rename_test() {
  let fields = [#("child", forest.FieldDelta([]))]
  let change =
    optional_field.FieldChange(
      [#(atom(1), atom(2))],
      [
        #(optional_field.Active, atom(40)),
        #(optional_field.Detached(atom(3)), atom(41)),
      ],
      Some(optional_field.Replacement(
        False,
        Some(optional_field.Detached(atom(4))),
        atom(5),
      )),
    )
  optional_field.into_delta(change, fn(_) { Ok(fields) })
  |> expect.to_equal(
    Ok(
      optional_field.FieldChangeDelta(
        Some(
          forest.FieldDelta([
            forest.Mark(1, Some(atom(4)), Some(atom(5)), fields),
          ]),
        ),
        [forest.DetachedChange(atom(3), fields)],
        [forest.Rename(atom(1), atom(2), 1)],
      ),
    ),
  )
  optional_field.into_delta(
    optional_field.FieldChange(
      [],
      [],
      Some(optional_field.Replacement(
        False,
        Some(optional_field.Active),
        atom(8),
      )),
    ),
    fn(_) { Ok([]) },
  )
  |> expect.to_equal(Ok(optional_field.FieldChangeDelta(None, [], [])))
  optional_field.into_delta(
    optional_field.FieldChange([], [#(optional_field.Active, atom(40))], None),
    fn(_) { Ok([]) },
  )
  |> expect.to_equal(
    Ok(
      optional_field.FieldChangeDelta(
        Some(forest.FieldDelta([forest.Mark(1, None, None, [])])),
        [],
        [],
      ),
    ),
  )
}

pub fn shared_tree_field_required_schema_refuses_clear_delta_test() {
  let assert Ok(stored) =
    schema.stored_from_string(
      "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}}},\"root\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}",
    )
  let assert Ok(state) =
    forest.new(
      revision("00000000-0000-4000-8000-000000000001"),
      stored,
      Some(NumberValue(1.0)),
    )
  let assert Ok(field_delta) =
    optional_field.into_delta(optional_field.clear(False, atom(6)), fn(_) {
      Ok([])
    })
  let assert Some(local) = field_delta.local
  let assert Ok(delta) =
    forest.delta(
      forest.DeltaData(
        latest_revision: atom(6).revision,
        fields: [#("rootFieldKey", local)],
        build: [],
        refreshers: [],
        global: field_delta.global,
        rename: field_delta.rename,
        destroy: [],
      ),
    )
  let assert Error(_) = forest.apply_delta(state, delta)
  Nil
}

pub fn shared_tree_field_composed_application_matches_sequential_test() {
  let first = optional_field.set(False, atom(0), atom(1))
  let second = optional_field.set(False, atom_b(2), atom_b(3))
  let initial = [
    #(optional_field.Active, "old"),
    #(optional_field.Detached(atom(0)), "first"),
    #(optional_field.Detached(atom_b(2)), "second"),
  ]
  let sequential = apply_change(apply_change(initial, first), second)
  let composed = apply_change(initial, compose_without_children(first, second))
  assert_registers_equal(sequential, composed, [
    optional_field.Active,
    optional_field.Detached(atom(0)),
    optional_field.Detached(atom(1)),
    optional_field.Detached(atom_b(2)),
    optional_field.Detached(atom_b(3)),
  ])
}

pub fn shared_tree_field_rollback_restores_registers_and_undo_restores_value_test() {
  let change = optional_field.set(False, atom(0), atom(1))
  let initial = [
    #(optional_field.Active, "old"),
    #(optional_field.Detached(atom(0)), "new"),
  ]
  let changed = apply_change(initial, change)
  let inverse_revision = Some(revision("00000000-0000-4000-8000-0000000000c0"))
  let assert Ok(#(rollback, -1)) =
    optional_field.invert(change, True, inverse_revision, -1)
  let rolled_back = apply_change(changed, rollback)
  assert_registers_equal(initial, rolled_back, [
    optional_field.Active,
    optional_field.Detached(atom(0)),
    optional_field.Detached(atom(1)),
  ])

  let assert Ok(#(undo, 0)) =
    optional_field.invert(change, False, inverse_revision, -1)
  let undone = apply_change(changed, undo)
  read_register(undone, optional_field.Active)
  |> expect.to_equal(Some("old"))
  read_register(undone, optional_field.Detached(AtomId(inverse_revision, 0)))
  |> expect.to_equal(Some("new"))
}

pub fn shared_tree_field_composition_is_associative_in_valid_context_test() {
  let first = optional_field.set(False, atom(0), atom(1))
  let second = optional_field.set(False, atom_b(2), atom_b(3))
  let third = optional_field.clear(False, atom(4))
  let initial = [
    #(optional_field.Active, "old"),
    #(optional_field.Detached(atom(0)), "first"),
    #(optional_field.Detached(atom_b(2)), "second"),
  ]
  let left =
    compose_without_children(compose_without_children(first, second), third)
  let right =
    compose_without_children(first, compose_without_children(second, third))
  assert_registers_equal(
    apply_change(initial, left),
    apply_change(initial, right),
    [
      optional_field.Active,
      optional_field.Detached(atom(0)),
      optional_field.Detached(atom(1)),
      optional_field.Detached(atom_b(2)),
      optional_field.Detached(atom_b(3)),
      optional_field.Detached(atom(4)),
    ],
  )
}

pub fn shared_tree_field_rebase_over_rollback_pair_restores_change_test() {
  let authored = optional_field.set(False, atom(0), atom(1))
  let base = optional_field.clear(False, atom_b(2))
  let assert Ok(#(base_inverse, _)) =
    optional_field.invert(
      base,
      True,
      Some(revision("00000000-0000-4000-8000-0000000000c0")),
      -1,
    )
  let rebased = rebase_without_children(authored, base)
  rebase_without_children(rebased, base_inverse)
  |> expect.to_equal(authored)
}

fn compose_without_children(
  first: optional_field.FieldChange,
  second: optional_field.FieldChange,
) -> optional_field.FieldChange {
  let assert Ok(#(change, Nil)) =
    optional_field.compose(first, second, Nil, fn(left, right, state) {
      let assert Some(id) = left |> option.or(right)
      Ok(#(id, state))
    })
  change
}

fn rebase_without_children(
  change: optional_field.FieldChange,
  over: optional_field.FieldChange,
) -> optional_field.FieldChange {
  let assert Ok(#(change, Nil)) =
    optional_field.rebase(change, over, Nil, fn(current, base, _, state) {
      Ok(#(current |> option.or(base), state))
    })
  change
}

fn apply_change(
  state: List(#(optional_field.RegisterId, String)),
  change: optional_field.FieldChange,
) -> List(#(optional_field.RegisterId, String)) {
  let optional_field.FieldChange(moves, _, replacement) = change
  let transfers =
    list.map(moves, fn(move) {
      #(optional_field.Detached(move.0), optional_field.Detached(move.1))
    })
  let transfers = case replacement {
    None -> transfers
    Some(replacement) -> {
      let transfers = case replacement.was_empty {
        True -> transfers
        False ->
          list.append(transfers, [
            #(
              optional_field.Active,
              optional_field.Detached(replacement.detach_id),
            ),
          ])
      }
      case replacement.source {
        None -> transfers
        Some(source) ->
          list.append(transfers, [#(source, optional_field.Active)])
      }
    }
  }
  let original = state
  let remaining =
    list.fold(transfers, state, fn(state, transfer) {
      remove_register(state, transfer.0)
    })
  list.fold(transfers, remaining, fn(state, transfer) {
    put_register(state, transfer.1, read_register(original, transfer.0))
  })
}

fn read_register(
  state: List(#(optional_field.RegisterId, String)),
  register: optional_field.RegisterId,
) -> Option(String) {
  case list.find(state, fn(entry) { entry.0 == register }) {
    Ok(entry) -> Some(entry.1)
    Error(Nil) -> None
  }
}

fn remove_register(
  state: List(#(optional_field.RegisterId, String)),
  register: optional_field.RegisterId,
) -> List(#(optional_field.RegisterId, String)) {
  list.filter(state, fn(entry) { entry.0 != register })
}

fn put_register(
  state: List(#(optional_field.RegisterId, String)),
  register: optional_field.RegisterId,
  value: Option(String),
) -> List(#(optional_field.RegisterId, String)) {
  let state = remove_register(state, register)
  case value {
    None -> state
    Some(value) -> [#(register, value), ..state]
  }
}

fn assert_registers_equal(
  first: List(#(optional_field.RegisterId, String)),
  second: List(#(optional_field.RegisterId, String)),
  registers: List(optional_field.RegisterId),
) -> Nil {
  list.each(registers, fn(register) {
    read_register(first, register)
    |> expect.to_equal(read_register(second, register))
  })
}
