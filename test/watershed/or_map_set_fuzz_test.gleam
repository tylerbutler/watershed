import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/or_map
import lattice_sets/or_set
import qcheck
import startest/expect
import watershed/fuzz/kernel_fuzz.{
  type Command, type KernelModel, AddClient, Capabilities, ClientOperation,
  Deliver, Disconnect, KernelModel, OperationEntry, Reconnect, RollbackOperation,
  Sequence, SequencedMeta, StashedOperation, SubmitMeta, Synchronize,
}
import watershed/fuzz/or_map_metadata
import watershed/fuzz/or_map_set_model.{
  type Dot, type Intent, type Observation, type SetMapCommand,
  type SetObservation, type State, AddMember, Context, Observation, RemoveKey,
  RemoveMember, SetMapCommand, SetObservation, State,
}
import watershed/fuzz/script_gen
import watershed/or_map_kernel as kernel
import watershed/or_map_set_leaf

type Model =
  KernelModel(State, SetMapCommand, Observation)

fn edit(intent: Intent, key: String, member: String) -> SetMapCommand {
  SetMapCommand(intent, key, member, None, None)
}

fn key_dot(author: String, key: String, counter: Int) -> Dot {
  #(or_map_metadata.membership_author(author, key, #(0, None)), counter)
}

pub fn generated_stash_fixture_contains_original_payload_test() -> Nil {
  let model = or_map_set_model.model()
  qcheck.run(
    qcheck.default_config() |> qcheck.with_test_count(20),
    model.gen_operation,
    fn(original) {
      expect.to_be_false(original.context == None)
      expect.to_be_false(original.delta == None)
      let script = [
        ClientOperation(2, edit(AddMember, original.key, "later")),
        Synchronize,
        StashedOperation(1, original),
        StashedOperation(1, original),
        Synchronize,
      ]
      let assert Ok(decoded) =
        json.parse(
          kernel_fuzz.script_to_json(model.operation_to_json, script)
            |> json.to_string,
          kernel_fuzz.script_decoder(model.operation_decoder),
        )
      decoded |> expect.to_equal(script)
      kernel_fuzz.try_run_script(model, 3, decoded) |> expect.to_equal(Ok(Nil))
    },
  )
}

pub fn converges_and_matches_oracle_test() -> Nil {
  let model = or_map_set_model.model()
  kernel_fuzz.run(
    model,
    kernel_fuzz.config_from_environment(),
    3,
    script_gen.script_generator(
      model.gen_operation,
      3,
      script_gen.Weights(
        ..script_gen.default_weights(),
        rollback_operation: 8,
        stashed_operation: 8,
      ),
    ),
  )
}

pub fn independent_oracle_retracts_only_observed_dots_test() -> Nil {
  let old = #("client-1", 1)
  let concurrent = #("client-2", 2)
  let old_key = key_dot("client-1", "doc", 1)
  let removal = key_dot("client-1", "doc", 2)
  let concurrent_key = key_dot("client-2", "doc", 2)
  let entries = [
    OperationEntry(
      1,
      SetMapCommand(
        AddMember,
        "doc",
        "old",
        Some(Context(0, "client-1", 1, [], None, [], #(0, None))),
        None,
      ),
      [],
    ),
    OperationEntry(
      1,
      SetMapCommand(
        RemoveKey,
        "doc",
        "",
        Some(
          Context(
            1,
            "client-1",
            2,
            [old_key],
            Some(SetObservation([#("old", [old])], [])),
            [],
            #(0, None),
          ),
        ),
        None,
      ),
      [],
    ),
    OperationEntry(
      2,
      SetMapCommand(
        AddMember,
        "doc",
        "new",
        Some(
          Context(
            1,
            "client-2",
            2,
            [old_key],
            Some(SetObservation([#("old", [old])], [])),
            [],
            #(0, None),
          ),
        ),
        None,
      ),
      [],
    ),
  ]
  let expected =
    Observation(
      SetObservation([#("doc", [concurrent_key])], [old_key, removal]),
      [#("doc", SetObservation([#("new", [concurrent])], [old]))],
      [#("doc", [removal])],
      [#("doc", ["new"])],
      [#("doc", #(0, None))],
    )
  entries
  |> list.permutations
  |> list.each(fn(entries) {
    or_map_set_model.oracle(entries) |> expect.to_equal(expected)
  })
}

pub fn pending_members_and_independent_keys_test() -> Nil {
  let model = or_map_set_model.model()
  let script = [
    ClientOperation(1, edit(AddMember, "doc", "old")),
    ClientOperation(1, edit(AddMember, "other", "retained")),
    ClientOperation(1, edit(RemoveMember, "doc", "old")),
    ClientOperation(1, edit(AddMember, "doc", "new")),
    ClientOperation(1, edit(RemoveKey, "doc", "")),
    ClientOperation(1, edit(RemoveMember, "missing", "absent")),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(model, 3, script) |> expect.to_equal(Ok(Nil))
}

pub fn causal_races_rollback_and_reconnect_test() -> Nil {
  let model = or_map_set_model.model()
  let prefix = [
    ClientOperation(1, edit(AddMember, "doc", "old")),
    Synchronize,
  ]
  let races: List(List(Command(SetMapCommand))) = [
    [
      ClientOperation(1, edit(RemoveKey, "doc", "")),
      ClientOperation(2, edit(AddMember, "doc", "new")),
    ],
    [
      ClientOperation(2, edit(AddMember, "doc", "new")),
      ClientOperation(1, edit(RemoveKey, "doc", "")),
    ],
    [
      ClientOperation(1, edit(RemoveMember, "doc", "old")),
      ClientOperation(2, edit(AddMember, "doc", "old")),
    ],
    [
      ClientOperation(1, edit(AddMember, "doc", "old")),
      RollbackOperation(1, edit(AddMember, "other", "abandoned")),
      ClientOperation(1, edit(RemoveKey, "doc", "")),
      ClientOperation(1, edit(AddMember, "doc", "new")),
    ],
    [
      ClientOperation(1, edit(RemoveKey, "doc", "")),
      Disconnect(1),
      ClientOperation(2, edit(AddMember, "doc", "new")),
      Sequence(1),
      Deliver(1, 1),
      Reconnect(1),
    ],
  ]
  list.each(races, fn(race) {
    kernel_fuzz.try_run_script(model, 3, list.append(prefix, race))
    |> expect.to_equal(Ok(Nil))
  })
}

pub fn captured_stash_and_full_script_round_trip_test() -> Nil {
  let model = or_map_set_model.model()
  let #(_, routed) =
    model.submit(model.init(1), edit(AddMember, "", ""), SubmitMeta(1, 0))
  let assert Some(original) = routed
  let script = [
    StashedOperation(1, original),
    Synchronize,
    ClientOperation(1, edit(RemoveKey, "", "")),
    Synchronize,
    ClientOperation(1, edit(AddMember, "", "new")),
    StashedOperation(1, original),
    StashedOperation(1, original),
    Synchronize,
  ]
  let assert Ok(decoded) =
    json.parse(
      kernel_fuzz.script_to_json(model.operation_to_json, script)
        |> json.to_string,
      kernel_fuzz.script_decoder(model.operation_decoder),
    )
  decoded |> expect.to_equal(script)
  kernel_fuzz.try_run_script(model, 3, decoded) |> expect.to_equal(Ok(Nil))
}

fn submitted(
  model: Model,
  state: State,
  intent: Intent,
  key: String,
  member: String,
) -> #(State, SetMapCommand) {
  let #(state, command) =
    model.submit(state, edit(intent, key, member), SubmitMeta(1, 0))
  let assert Some(command) = command
  #(state, command)
}

fn delivered(model: Model, state: State, command: SetMapCommand) -> State {
  let assert Ok(state) =
    model.apply_remote(state, command, SequencedMeta(0, 1, 1, 0, [0, 1, 2]))
  or_map_set_model.check(state) |> expect.to_equal(Ok(Nil))
  state
}

pub fn missing_empty_duplicate_and_noop_events_test() -> Nil {
  let model = or_map_set_model.model()
  let initial = model.init(1)
  let #(missing, noop) = submitted(model, initial, RemoveMember, "", "")
  model.observe(missing)
  |> expect.to_equal(or_map_set_model.empty_observation())
  missing.floor |> expect.to_equal(0)
  noop.delta
  |> expect.to_equal(Some(or_map.empty_delta(initial.actual.optimistic)))
  let assert Ok(#(_, events, _, _)) =
    kernel.remove_member(initial.actual, "", "")
  events |> expect.to_equal([])
  let assert Ok(#(_, events, operation, _)) = kernel.remove(initial.actual, "")
  events |> expect.to_equal([])
  let assert kernel.Remove(_, delta) = operation
  delta |> expect.to_equal(or_map.empty_delta(initial.actual.optimistic))

  let #(first, _) = submitted(model, initial, AddMember, "", "")
  let assert Ok(#(_, events, _, _)) = kernel.add_member(first.actual, "", "")
  events |> expect.to_equal([])
  let #(duplicate, _) = submitted(model, first, AddMember, "", "")
  let first_view = model.observe(first)
  let duplicate_view = model.observe(duplicate)
  first_view.visible |> expect.to_equal([#("", [""])])
  duplicate_view.visible |> expect.to_equal(first_view.visible)
  expect.to_be_false(duplicate_view == first_view)
  duplicate_view.keys.entries
  |> expect.to_equal([
    #("", [key_dot("client-1", "", 1), key_dot("client-1", "", 2)]),
  ])

  let #(empty, _) = submitted(model, duplicate, RemoveMember, "", "")
  let empty_view = model.observe(empty)
  empty_view.visible |> expect.to_equal([#("", [])])
  let #(unchanged, _) = submitted(model, empty, RemoveMember, "", "")
  model.observe(unchanged) |> expect.to_equal(empty_view)
  unchanged.floor |> expect.to_equal(empty.floor)
  let #(removed, _) = submitted(model, unchanged, RemoveKey, "", "")
  model.observe(removed).visible |> expect.to_equal([])
  [missing, first, duplicate, empty, unchanged, removed]
  |> list.each(fn(state) {
    or_map_set_model.check(state) |> expect.to_equal(Ok(Nil))
  })
}

pub fn utf8_keys_and_members_have_literal_canonical_order_test() -> Nil {
  let model = or_map_set_model.model()
  let state =
    ["\u{10000}", "\u{e000}", "é", ""]
    |> list.fold(model.init(1), fn(state, key) {
      ["\u{10000}", "\u{e000}", "é", ""]
      |> list.fold(state, fn(state, member) {
        submitted(model, state, AddMember, key, member).0
      })
    })
  model.observe(state).visible
  |> expect.to_equal([
    #("", ["", "é", "\u{e000}", "\u{10000}"]),
    #("é", ["", "é", "\u{e000}", "\u{10000}"]),
    #("\u{e000}", ["", "é", "\u{e000}", "\u{10000}"]),
    #("\u{10000}", ["", "é", "\u{e000}", "\u{10000}"]),
  ])
  or_map_set_model.check(state) |> expect.to_equal(Ok(Nil))
}

pub fn delayed_remove_stash_keeps_original_observation_test() -> Nil {
  let model = or_map_set_model.model()
  let assert Some(stash) = model.capabilities.apply_stashed
  let #(original_state, old) =
    submitted(model, model.init(1), AddMember, "doc", "old")
  // The original remove sees its own pending add, despite reference zero.
  let #(_, removal) = submitted(model, original_state, RemoveKey, "doc", "")
  let assert Some(context) = removal.context
  context.reference_sequence_number |> expect.to_equal(0)
  context.key_dots |> expect.to_equal([key_dot("client-1", "doc", 1)])

  let receiver = delivered(model, model.init(2), old)
  let #(receiver, update) = submitted(model, receiver, AddMember, "doc", "new")
  let #(receiver, replayed) = stash(receiver, removal, SubmitMeta(2, 99))
  replayed |> expect.to_equal(removal)
  model.observe(receiver).visible |> expect.to_equal([#("doc", ["new"])])
  or_map_set_model.check(receiver) |> expect.to_equal(Ok(Nil))

  let script = [
    StashedOperation(1, old),
    StashedOperation(2, update),
    Synchronize,
    StashedOperation(1, removal),
    Synchronize,
    StashedOperation(1, removal),
    StashedOperation(1, old),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(model, 3, script) |> expect.to_equal(Ok(Nil))
}

pub fn out_of_order_and_duplicate_delivery_matches_dot_oracle_test() -> Nil {
  let model = or_map_set_model.model()
  let #(a, old) = submitted(model, model.init(1), AddMember, "doc", "old")
  let #(a, remove) = submitted(model, a, RemoveKey, "doc", "")
  let #(_, readd) = submitted(model, a, AddMember, "doc", "readded")
  let b = delivered(model, model.init(2), old)
  let #(_, concurrent) = submitted(model, b, AddMember, "doc", "concurrent")
  let operations = [old, remove, readd, concurrent]
  let expected =
    operations
    |> list.map(fn(command) { OperationEntry(1, command, []) })
    |> or_map_set_model.oracle
  expected.visible |> expect.to_equal([#("doc", ["readded"])])
  operations
  |> list.permutations
  |> list.each(fn(ordered) {
    let state =
      list.append(ordered, [old, remove, old])
      |> list.fold(model.init(0), fn(state, command) {
        delivered(model, state, command)
      })
    model.observe(state) |> expect.to_equal(expected)
  })
}

pub fn stale_stash_preserves_original_payload_without_restamping_test() -> Nil {
  let model = or_map_set_model.model()
  let assert Some(stash) = model.capabilities.apply_stashed
  let #(state, old) = submitted(model, model.init(1), AddMember, "doc", "old")
  let #(state, _) = submitted(model, state, RemoveKey, "doc", "")
  let #(state, _) = submitted(model, state, AddMember, "doc", "new")
  let #(state, replayed) = stash(state, old, SubmitMeta(1, 999))
  replayed |> expect.to_equal(old)
  model.observe(state).visible |> expect.to_equal([#("doc", ["new"])])
  or_map_set_model.check(state) |> expect.to_equal(Ok(Nil))
}

pub fn same_and_different_author_reload_retains_history_and_floors_test() -> Nil {
  let model = or_map_set_model.model()
  let assert Some(load) = model.capabilities.load_from_synced
  let assert Some(rollback) = model.capabilities.rollback
  let #(state, abandoned) =
    submitted(model, model.init(1), AddMember, "absent", "old")
  let state = rollback(state, abandoned)
  let #(state, older) = submitted(model, state, AddMember, "doc", "old")
  let assert Ok(state) =
    model.ack_local(state, older, SequencedMeta(1, 1, 1, 0, [1]))
  let #(state, removal) = submitted(model, state, RemoveKey, "doc", "")
  let assert Ok(state) =
    model.ack_local(state, removal, SequencedMeta(1, 1, 2, 0, [1]))
  [1, 2]
  |> list.each(fn(id) {
    let loaded = load(state, id)
    model.observe(loaded) |> expect.to_equal(model.observe(state))
    expect.to_be_true(loaded.actual.set_clocks.key_counter >= state.floor)
    let #(loaded, fresh) = submitted(model, loaded, AddMember, "absent", "new")
    let assert Some(context) = fresh.context
    expect.to_be_true(context.counter > state.floor)
    context.author
    |> expect.to_equal(case id {
      1 -> "client-1"
      _ -> "client-2"
    })
    or_map_set_model.check(loaded) |> expect.to_equal(Ok(Nil))
    let loaded = delivered(model, loaded, older)
    model.observe(loaded).visible |> expect.to_equal([#("absent", ["new"])])
  })
}

pub fn cursors_remain_local_after_rollback_test() -> Nil {
  let model = or_map_set_model.model()
  let assert Some(rollback) = model.capabilities.rollback
  let #(writer, abandoned) =
    submitted(model, model.init(1), AddMember, "doc", "old")
  let writer = rollback(writer, abandoned)
  let observer = model.init(0)
  model.observe(writer) |> expect.to_equal(model.observe(observer))
  writer.actual.set_clocks.key_counter |> expect.to_equal(1)
  observer.actual.set_clocks.key_counter |> expect.to_equal(0)
  [writer, observer]
  |> list.each(fn(state) {
    or_map_set_model.check(state) |> expect.to_equal(Ok(Nil))
  })
}

pub fn rollback_empty_checkpoint_reload_does_not_reuse_either_dot_test() -> Nil {
  let model = or_map_set_model.model()
  let assert Some(rollback) = model.capabilities.rollback
  let assert Some(load) = model.capabilities.load_from_synced
  let #(state, abandoned) =
    submitted(model, model.init(1), AddMember, "absent", "old")
  let state = rollback(state, abandoned)
  let loaded = load(state, 1)
  model.observe(loaded) |> expect.to_equal(or_map_set_model.empty_observation())
  let #(fresh, command) = submitted(model, loaded, AddMember, "absent", "new")
  let assert Some(context) = command.context
  context.counter |> expect.to_equal(2)
  model.observe(fresh).keys.entries
  |> expect.to_equal([#("absent", [key_dot("client-1", "absent", 2)])])
  model.observe(fresh).members
  |> expect.to_equal([
    #("absent", SetObservation([#("new", [#("client-1", 2)])], [])),
  ])
  or_map_set_model.check(fresh) |> expect.to_equal(Ok(Nil))
}

pub fn operation_round_trip_preserves_all_captured_metadata_test() -> Nil {
  let model = or_map_set_model.model()
  let #(state, add) = submitted(model, model.init(1), AddMember, "", "old")
  let #(state, remove_member) = submitted(model, state, RemoveMember, "", "old")
  let #(state, remove_key) = submitted(model, state, RemoveKey, "", "")
  let #(_, readd) = submitted(model, state, AddMember, "", "new")
  let assert Some(context) = readd.context
  context.removal_bound |> expect.to_equal([key_dot("client-1", "", 3)])
  context.members
  |> expect.to_equal(Some(SetObservation([], [#("client-1", 1)])))
  [
    edit(AddMember, "", ""),
    edit(RemoveMember, "", ""),
    edit(RemoveKey, "", ""),
    add,
    remove_member,
    remove_key,
    readd,
  ]
  |> list.each(fn(command) {
    json.parse(
      model.operation_to_json(command) |> json.to_string,
      model.operation_decoder,
    )
    |> expect.to_equal(Ok(command))
  })
  [
    SetMapCommand(..readd, context: None),
    SetMapCommand(..readd, delta: None),
  ]
  |> list.each(fn(command) {
    json.parse(
      model.operation_to_json(command) |> json.to_string,
      model.operation_decoder,
    )
    |> result.is_error
    |> expect.to_be_true()
  })
}

fn vector_json(clocks: List(#(String, Int))) -> json.Json {
  json.object([
    #("type", json.string("version_vector")),
    #("v", json.int(1)),
    #(
      "state",
      json.object([
        #(
          "clocks",
          json.object(
            list.map(clocks, fn(pair) { #(pair.0, json.int(pair.1)) }),
          ),
        ),
      ]),
    ),
  ])
}

fn dot_json(dot: Dot) -> json.Json {
  json.object([#("r", json.string(dot.0)), #("c", json.int(dot.1))])
}

fn set_json(state: SetObservation, author: String, counter: Int) -> json.Json {
  json.object([
    #("type", json.string("or_set")),
    #("v", json.int(3)),
    #(
      "state",
      json.object([
        #("replica_id", json.string(author)),
        #("counter", json.int(counter)),
        #(
          "entries",
          json.array(state.entries, fn(pair) {
            json.object([
              #("value", json.string(pair.0)),
              #("tags", json.array(pair.1, dot_json)),
            ])
          }),
        ),
        #("tombstones", json.array(state.tombstones, dot_json)),
        #("pruned", vector_json([])),
      ]),
    ),
  ])
}

// These encoders plant faults in native inputs. They never calculate winners.
fn native_json(
  observation: Observation,
  author: String,
  counter: Int,
  is_delta: Bool,
) -> String {
  json.object([
    #(
      "type",
      json.string(case is_delta {
        True -> "or_map_delta"
        False -> "or_map"
      }),
    ),
    #(
      "v",
      json.int(case is_delta {
        True -> 2
        False -> 3
      }),
    ),
    #(
      "state",
      json.object([
        #("replica_id", json.string(author)),
        #(
          "spec",
          crdt.spec_to_json_with(crdt.OrSetSpec, json.string)
            |> json.to_string
            |> json.string,
        ),
        #("clock", json.int(counter)),
        #(
          "entries",
          json.array(observation.generations, fn(pair) {
            let key = pair.0
            let bounds =
              result.unwrap(list.key_find(observation.bounds, key), [])
            let membership =
              SetObservation(
                list.filter(observation.keys.entries, fn(entry) {
                  entry.0 == key
                }),
                list.filter(observation.keys.tombstones, fn(dot) {
                  dot.1 <= result.unwrap(list.key_find(bounds, dot.0), 0)
                }),
              )
            let leaf = case list.key_find(observation.members, key) {
              Error(Nil) -> json.null()
              Ok(leaf) -> {
                let leaf = set_json(leaf, author, counter) |> json.to_string
                case is_delta {
                  False -> json.string(leaf)
                  True -> {
                    let assert Ok(leaf) =
                      or_set.from_json_with(leaf, decode.string)
                    crdt.delta_to_json(crdt.StateDelta(crdt.CrdtOrSet(leaf)))
                    |> json.to_string
                    |> json.string
                  }
                }
              }
            }
            json.object([
              #("key", json.string(key)),
              #("generation", or_map_metadata.generation_json(pair.1)),
              #(
                "membership",
                set_json(
                  membership,
                  or_map_metadata.membership_author(author, key, pair.1),
                  counter,
                )
                  |> json.to_string
                  |> json.string,
              ),
              #("value", leaf),
            ])
          }),
        ),
      ]),
    ),
  ])
  |> json.to_string
}

fn replace_native(
  state: State,
  observation: Observation,
  counter: Int,
) -> State {
  let assert Ok(map) =
    or_map.from_json(native_json(observation, state.author, counter, False))
  State(
    ..state,
    actual: kernel.OrMapState(..state.actual, sequenced: map, optimistic: map),
  )
}

pub fn shared_leaf_author_command() -> SetMapCommand {
  let model = or_map_set_model.model()
  let #(_, original) =
    submitted(model, model.init(1), AddMember, "doc", "member")
  let contribution = or_map_set_model.contribution(original)
  let wrong_leaf = SetObservation([#("member", [#("shared-leaf", 1)])], [])
  let assert Ok(delta) =
    or_map.delta_from_json(native_json(
      Observation(..contribution, members: [#("doc", wrong_leaf)]),
      "client-1",
      1,
      True,
    ))
  SetMapCommand(..original, delta: Some(delta))
}

fn expect_fault(
  model: Model,
  script: List(Command(SetMapCommand)),
  detail: String,
) -> Nil {
  let assert Error(found) = kernel_fuzz.try_run_script(model, 3, script)
  string.contains(found, detail) |> expect.to_be_true()
}

pub fn shared_leaf_writer_identity_is_detected_test() -> Nil {
  let model = or_map_set_model.model()
  let faulty = shared_leaf_author_command()
  let script = [
    StashedOperation(1, faulty),
    ClientOperation(2, edit(AddMember, "doc", "other")),
    Synchronize,
  ]
  expect_fault(model, script, "causal state differs from independent oracle")
}

pub fn rollback_counter_rewind_is_detected_without_visible_change_test() -> Nil {
  let model = or_map_set_model.model()
  let assert Some(rollback) = model.capabilities.rollback
  let buggy =
    KernelModel(
      ..model,
      capabilities: Capabilities(
        ..model.capabilities,
        rollback: Some(fn(state, command) {
          let state = rollback(state, command)
          let state = replace_native(state, model.observe(state), 0)
          State(
            ..state,
            actual: kernel.OrMapState(
              ..state.actual,
              set_clocks: or_map_set_leaf.new_clocks(),
            ),
          )
        }),
      ),
    )
  let script = [RollbackOperation(1, edit(AddMember, "doc", "abandoned"))]
  kernel_fuzz.try_run_script(model, 3, script) |> expect.to_equal(Ok(Nil))
  expect_fault(buggy, script, "Counter floor rewound")
}

pub fn reload_dropped_tombstones_and_generations_are_detected_test() -> Nil {
  let model = or_map_set_model.model()
  let assert Some(load) = model.capabilities.load_from_synced
  let prefix = [
    ClientOperation(1, edit(AddMember, "doc", "old")),
    ClientOperation(1, edit(RemoveKey, "doc", "")),
  ]
  [[], [ClientOperation(1, edit(AddMember, "doc", "new"))]]
  |> list.each(fn(readd) {
    let script =
      list.append(prefix, list.append(readd, [Synchronize, AddClient]))
    kernel_fuzz.try_run_script(model, 3, script) |> expect.to_equal(Ok(Nil))
    // A fresh generation replaces the old membership tombstones.
    let faults = case readd {
      [] -> [0, 1, 2]
      _ -> [1, 2]
    }
    faults
    |> list.each(fn(fault) {
      let buggy =
        KernelModel(
          ..model,
          capabilities: Capabilities(
            ..model.capabilities,
            load_from_synced: Some(fn(state, id) {
              let state = load(state, id)
              let observation = model.observe(state)
              let changed = case fault {
                0 ->
                  Observation(
                    ..observation,
                    keys: SetObservation(..observation.keys, tombstones: []),
                  )
                1 ->
                  Observation(
                    ..observation,
                    members: list.map(observation.members, fn(pair) {
                      #(pair.0, SetObservation(..pair.1, tombstones: []))
                    }),
                  )
                _ -> Observation(..observation, generations: [])
              }
              replace_native(state, changed, state.floor)
            }),
          ),
        )
      expect_fault(buggy, script, "Confirmed causal state differs")
    })
  })
}

pub fn inactive_imported_members_are_observed_and_cleared_on_readd_test() -> Nil {
  let model = or_map_set_model.model()
  let retained =
    Observation(
      SetObservation([], [#("client-1", 1)]),
      [#("doc", SetObservation([#("old", [#("client-1", 1)])], []))],
      [#("doc", [#("client-1", 1)])],
      [],
      [#("doc", #(0, None))],
    )
  let assert Ok(actual) =
    kernel.from_summary(
      native_json(retained, "client-1", 1, False),
      replica_id.new("client-1"),
    )
  let imported =
    State(..model.init(1), actual: actual, confirmed: retained, floor: 1)
  or_map_set_model.check(imported) |> expect.to_equal(Ok(Nil))
  let #(state, _) = submitted(model, imported, AddMember, "doc", "new")
  let observation = model.observe(state)
  observation.visible |> expect.to_equal([#("doc", ["new"])])
  observation.members
  |> expect.to_equal([
    #("doc", SetObservation([#("new", [#("client-1", 2)])], [#("client-1", 1)])),
  ])
  or_map_set_model.check(state) |> expect.to_equal(Ok(Nil))
}

pub fn retained_member_resurrection_is_detected_test() -> Nil {
  let model = or_map_set_model.model()
  let #(state, old) = submitted(model, model.init(1), AddMember, "doc", "old")
  let #(state, removal) = submitted(model, state, RemoveKey, "doc", "")
  let #(_, readd) = submitted(model, state, AddMember, "doc", "new")
  let readded = or_map_set_model.contribution(readd)
  let assert Ok(delta) =
    or_map.delta_from_json(native_json(
      Observation(..readded, members: [
        #(
          "doc",
          SetObservation(
            [#("new", [#("client-1", 3)]), #("old", [#("client-1", 4)])],
            [#("client-1", 1)],
          ),
        ),
      ]),
      "client-1",
      4,
      True,
    ))
  let buggy_readd = SetMapCommand(..readd, delta: Some(delta))
  let prefix = [
    StashedOperation(1, old),
    StashedOperation(1, removal),
    Synchronize,
  ]
  kernel_fuzz.try_run_script(
    model,
    3,
    list.append(prefix, [StashedOperation(1, readd)]),
  )
  |> expect.to_equal(Ok(Nil))
  expect_fault(
    model,
    list.append(prefix, [StashedOperation(1, buggy_readd)]),
    "causal state differs from independent oracle",
  )
}

pub fn absent_member_removal_creating_key_is_detected_test() -> Nil {
  let model = or_map_set_model.model()
  let #(state, old) =
    submitted(model, model.init(1), AddMember, "missing", "old")
  let #(state, removal) = submitted(model, state, RemoveKey, "missing", "")
  let #(_, noop) = submitted(model, state, RemoveMember, "missing", "absent")
  let assert Ok(delta) =
    or_map.delta_from_json(native_json(
      Observation(
        SetObservation([#("missing", [#("client-1", 3)])], []),
        [#("missing", SetObservation([], [#("client-1", 1)]))],
        [],
        [#("missing", [])],
        [#("missing", #(0, None))],
      ),
      "client-1",
      3,
      True,
    ))
  let faulty = SetMapCommand(..noop, delta: Some(delta))
  kernel.validate_operation(
    kernel.OrSetMode,
    or_map_set_model.operation(faulty),
  )
  |> expect.to_equal(Ok(Nil))
  expect_fault(
    model,
    [
      StashedOperation(1, old),
      StashedOperation(1, removal),
      Synchronize,
      StashedOperation(1, faulty),
    ],
    "causal state differs from independent oracle",
  )
}
