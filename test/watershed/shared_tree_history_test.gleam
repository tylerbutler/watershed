import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import startest/expect
import watershed/fluid_ids
import watershed/json_ot.{type JsonValue, VArray, VObject}
import watershed/tree/change
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/history
import watershed/tree/schema
import watershed/tree/schema_evolution_fixture
import watershed/tree/shared_change
import watershed/tree/types.{
  type TreeError, InvalidHistory, NumberValue, ObjectValue, SetField,
}

const tree_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"Point\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"y\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"Root\":{\"kind\":{\"object\":{\"point\":{\"kind\":\"Value\",\"types\":[\"Point\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

const optional_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},\"Point\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"y\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"Root\":{\"kind\":{\"object\":{\"point\":{\"kind\":\"Value\",\"types\":[\"Point\"]},\"note\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

const score_schema = "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},\"Point\":{\"kind\":{\"object\":{\"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]},\"y\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}}}},\"Root\":{\"kind\":{\"object\":{\"point\":{\"kind\":\"Value\",\"types\":[\"Point\"]},\"score\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.number\"]}}}}},\"root\":{\"kind\":\"Value\",\"types\":[\"Root\"]}}"

fn session(value: String) -> fluid_ids.SessionId {
  let assert Ok(id) = fluid_ids.session_id(value)
  id
}

fn revision(value: String) -> fluid_ids.StableId {
  let assert Ok(id) = fluid_ids.stable_id(value)
  id
}

fn local_session() -> fluid_ids.SessionId {
  session("00000000-0000-4000-8000-000000000001")
}

fn peer_session() -> fluid_ids.SessionId {
  session("00000000-0000-4000-8000-000000000002")
}

fn other_peer_session() -> fluid_ids.SessionId {
  session("00000000-0000-4000-8000-000000000003")
}

fn revision_a() -> fluid_ids.StableId {
  revision("00000000-0000-4000-8000-00000000000a")
}

fn revision_b() -> fluid_ids.StableId {
  revision("00000000-0000-4000-8000-00000000000b")
}

fn revision_r() -> fluid_ids.StableId {
  revision("00000000-0000-4000-8000-00000000000c")
}

type Allocation {
  Allocation(
    revisions: List(fluid_ids.StableId),
    order: change.IdentityOrder,
    consumed: Int,
  )
}

fn no_mint(
  state: Nil,
) -> Result(#(fluid_ids.StableId, change.IdentityOrder, Nil), TreeError) {
  let _ = state
  Error(InvalidHistory("unexpected rollback allocation"))
}

fn mint(
  state: Allocation,
) -> Result(#(fluid_ids.StableId, change.IdentityOrder, Allocation), TreeError) {
  case state.revisions {
    [] -> Error(InvalidHistory("rollback allocation is exhausted"))
    [revision, ..rest] ->
      Ok(#(
        revision,
        state.order,
        Allocation(rest, state.order, state.consumed + 1),
      ))
  }
}

fn empty_commit(
  revision: fluid_ids.StableId,
  originator: fluid_ids.SessionId,
) -> history.Commit {
  let assert Ok(order) = change.identity_order([#(revision, -1)])
  let assert Ok(checked) =
    change.from_data(change.to_data(change.empty()), order)
  history.Commit(revision, originator, shared_change.from_data(checked))
}

fn stored_schema() -> schema.StoredSchema {
  let assert Ok(stored) = schema.stored_from_string(tree_schema)
  stored
}

fn point(x: Float, y: Float) {
  ObjectValue("Point", [
    #("x", NumberValue(x)),
    #("y", NumberValue(y)),
  ])
}

fn root() {
  ObjectValue("Root", [#("point", point(1.0, 2.0))])
}

fn real_commit() -> #(history.Commit, forest.Forest) {
  let view = revision("00000000-0000-4000-8000-000000000099")
  let assert Ok(state) = forest.new(view, stored_schema(), Some(root()))
  let assert Ok(order) = change.identity_order([#(revision_a(), -1)])
  let assert Ok(authored) =
    change.edit(
      stored_schema(),
      state,
      revision_a(),
      SetField(["point", "x"], NumberValue(7.0)),
      order,
    )
  #(
    history.Commit(
      revision_a(),
      local_session(),
      shared_change.from_data(authored),
    ),
    state,
  )
}

fn conflicting_commits() -> #(
  history.Commit,
  history.Commit,
  forest.Forest,
  Allocation,
) {
  let view = revision("00000000-0000-4000-8000-000000000099")
  let assert Ok(state) = forest.new(view, stored_schema(), Some(root()))
  let assert Ok(authored_order) =
    change.identity_order([#(revision_a(), -2), #(revision_b(), -1)])
  let assert Ok(rollback_order) =
    change.identity_order([
      #(revision_a(), -2),
      #(revision_b(), -1),
      #(revision_r(), 0),
    ])
  let assert Ok(local) =
    change.edit(
      stored_schema(),
      state,
      revision_a(),
      SetField(["point", "x"], NumberValue(7.0)),
      authored_order,
    )
  let assert Ok(remote) =
    change.edit(
      stored_schema(),
      state,
      revision_b(),
      SetField(["point", "x"], NumberValue(8.0)),
      authored_order,
    )
  #(
    history.Commit(
      revision_a(),
      local_session(),
      shared_change.from_data(local),
    ),
    history.Commit(
      revision_b(),
      peer_session(),
      shared_change.from_data(remote),
    ),
    state,
    Allocation([revision_r()], rollback_order, 0),
  )
}

fn peer_edit(value: Float) -> history.Commit {
  let view = revision("00000000-0000-4000-8000-000000000099")
  let assert Ok(state) = forest.new(view, stored_schema(), Some(root()))
  let assert Ok(order) = change.identity_order([#(revision_a(), -1)])
  let assert Ok(authored) =
    change.edit(
      stored_schema(),
      state,
      revision_a(),
      SetField(["point", "x"], NumberValue(value)),
      order,
    )
  history.Commit(
    revision_a(),
    peer_session(),
    shared_change.from_data(authored),
  )
}

fn schema_commit(
  revision: fluid_ids.StableId,
  originator: fluid_ids.SessionId,
  before: schema.StoredSchema,
  after: schema.StoredSchema,
) -> history.Commit {
  let assert Ok(change) =
    shared_change.from_changes([
      shared_change.SchemaChange(
        schema.FixedSchema(before),
        schema.FixedSchema(after),
        False,
      ),
    ])
  history.Commit(revision, originator, change)
}

pub fn shared_tree_history_starts_empty_test() -> Nil {
  let state = history.new(local_session())
  history.pending(state) |> expect.to_equal([])
  history.inspect(state)
  |> expect.to_equal(history.HistoryView(
    history.HistorySnapshot(
      history.InitialBase,
      [],
      [],
      0,
      -9_007_199_254_740_991,
    ),
    [],
    0,
  ))
}

pub fn shared_tree_schema_evolution_history_test() -> Nil {
  let assert Ok(fixture) = fixtures.load("schema-evolution-history")
  let actual = run_history(fixture.input)
  let assert Ok(actual) = schema_evolution_fixture.history_projection(actual)
  let assert Ok(expected) =
    schema_evolution_fixture.history_projection(fixture.expected)
  case fixtures.first_difference(actual, expected) {
    Ok(Nil) -> Nil
    Error(path) -> panic as { "schema evolution history differs at " <> path }
  }
}

pub fn shared_tree_history_scenario_ids_do_not_change_observations_test() -> Nil {
  let assert Ok(fixture) = fixtures.load("schema-evolution-history")
  assert_history_scenario_rename(
    fixture.input,
    "pending-data-remote-upgrade",
    "renamed-pending-data-remote-upgrade",
  )
  assert_history_scenario_rename(
    fixture.input,
    "schema-schema-right-first",
    "renamed-schema-schema-right-first",
  )
}

pub fn shared_tree_history_summary_tail_mutation_changes_continuation_test() -> Nil {
  let assert Ok(fixture) = fixtures.load("schema-evolution-history")
  let original = run_history(fixture.input)
  let changed =
    fixture.input
    |> json.to_string
    |> string.replace("\"value\":\"tail\"", "\"value\":\"changed-tail\"")
  let assert Ok(changed) = json.parse(changed, json_ot.decoder())
  let mutated = run_history(json_ot.to_json(changed))
  observation_field(original, "summary-upgrade-plus-tail", "continuation")
  |> expect.to_not_equal(observation_field(
    mutated,
    "summary-upgrade-plus-tail",
    "continuation",
  ))
}

pub fn shared_tree_history_decode_mutation_changes_historical_decode_test() -> Nil {
  let assert Ok(fixture) = fixtures.load("schema-evolution-history")
  let original = run_history(fixture.input)
  let changed =
    fixture.input
    |> json.to_string
    |> string.replace(
      "\"value\":\"historical\"",
      "\"value\":\"changed-historical\"",
    )
  let assert Ok(changed) = json.parse(changed, json_ot.decoder())
  let mutated = run_history(json_ot.to_json(changed))
  observation_field(
    original,
    "historical-peer-schema-context",
    "historicalDecode",
  )
  |> expect.to_not_equal(observation_field(
    mutated,
    "historical-peer-schema-context",
    "historicalDecode",
  ))
}

pub fn shared_tree_history_captured_tail_bytes_drive_replay_test() -> Nil {
  let assert Ok(fixture) = fixtures.load("schema-evolution-history")
  let original = run_history(fixture.input)
  let mutated =
    schema_evolution_fixture.run_history_with_tail_replacement(
      fixture.input,
      "tail",
      "changed-wire-tail",
    )
    |> expect.to_be_ok()
  observation_field(original, "summary-upgrade-plus-tail", "continuation")
  |> expect.to_not_equal(observation_field(
    mutated,
    "summary-upgrade-plus-tail",
    "continuation",
  ))
}

pub fn shared_tree_history_corrupt_captured_tail_bytes_fail_test() -> Nil {
  let assert Ok(fixture) = fixtures.load("schema-evolution-history")
  let _ =
    schema_evolution_fixture.run_history_with_corrupt_tail(fixture.input)
    |> expect.to_be_error()
  Nil
}

pub fn shared_tree_history_semantic_projection_keeps_values_and_ids_test() -> Nil {
  let base =
    json.object([
      #(
        "changes",
        json.array(
          [
            json.object([
              #("type", json.string("data")),
              #(
                "innerChange",
                json.object([
                  #("maxLocalId", json.int(3)),
                  #(
                    "builds",
                    json.array(
                      [
                        json.object([
                          #(
                            "id",
                            json.object([
                              #("revision", json.string("revision-a")),
                              #("localId", json.int(2)),
                            ]),
                          ),
                          #(
                            "trees",
                            json.array(
                              [
                                json.object([
                                  #("kind", json.string("number")),
                                  #("value", json.float(2.5)),
                                ]),
                              ],
                              fn(value) { value },
                            ),
                          ),
                        ]),
                      ],
                      fn(value) { value },
                    ),
                  ),
                  #(
                    "destroys",
                    json.array(
                      [
                        json.object([
                          #("revision", json.string("revision-a")),
                          #("localId", json.int(3)),
                        ]),
                      ],
                      fn(value) { value },
                    ),
                  ),
                ]),
              ),
            ]),
          ],
          fn(value) { value },
        ),
      ),
    ])
  let changed_value =
    base
    |> json.to_string
    |> string.replace("\"value\":2.5", "\"value\":999.5")
    |> canonical_history_change()
  let changed_identity =
    base
    |> json.to_string
    |> string.replace("\"localId\":2", "\"localId\":8")
    |> canonical_history_change()
  let canonical = canonical_history_change(json.to_string(base))
  changed_value |> expect.to_not_equal(canonical)
  changed_identity |> expect.to_not_equal(canonical)
}

pub fn shared_tree_history_semantic_projection_keeps_json_looking_strings_test() -> Nil {
  let compact =
    json.object([
      #(
        "changes",
        json.array(
          [
            json.object([
              #("type", json.string("data")),
              #(
                "innerChange",
                json.object([#("value", json.string("{\"a\":1,\"b\":2}"))]),
              ),
            ]),
          ],
          fn(value) { value },
        ),
      ),
    ])
  let spaced =
    compact
    |> json.to_string
    |> string.replace(
      "\"{\\\"a\\\":1,\\\"b\\\":2}\"",
      "\"{ \\\"b\\\":2, \\\"a\\\":1 }\"",
    )

  canonical_history_change(json.to_string(compact))
  |> expect.to_not_equal(canonical_history_change(spaced))
}

fn observation_field(
  output: json.Json,
  id: String,
  field: String,
) -> JsonValue {
  let assert Ok(VObject(root)) =
    json.parse(json.to_string(output), json_ot.decoder())
  let assert Ok(VArray(observations)) = list.key_find(root, "observations")
  let assert Ok(VObject(observation)) =
    list.find(observations, fn(value) {
      case value {
        VObject(fields) ->
          list.key_find(fields, "id") == Ok(json_ot.VString(id))
        _ -> False
      }
    })
  let assert Ok(value) = list.key_find(observation, field)
  value
}

fn canonical_history_change(raw: String) -> json.Json {
  let assert Ok(value) = json.parse(raw, json_ot.decoder())
  schema_evolution_fixture.canonical_history_change(json_ot.to_json(value))
}

fn assert_history_scenario_rename(
  input: json.Json,
  before: String,
  after: String,
) -> Nil {
  let renamed_text =
    input
    |> json.to_string
    |> string.replace("\"" <> before <> "\"", "\"" <> after <> "\"")
  let assert Ok(renamed_value) = json.parse(renamed_text, json_ot.decoder())
  let renamed_input = json_ot.to_json(renamed_value)
  let original = run_history(input)
  let renamed = run_history(renamed_input)

  renamed
  |> json.to_string
  |> expect.to_equal(
    original
    |> json.to_string
    |> string.replace("\"" <> before <> "\"", "\"" <> after <> "\""),
  )
}

fn run_history(input: json.Json) -> json.Json {
  case schema_evolution_fixture.run_history(input) {
    Ok(output) -> output
    Error(detail) -> panic as { detail }
  }
}

pub fn shared_tree_history_schema_only_commit_retains_outer_revision_test() -> Nil {
  let assert Ok(outer) =
    shared_change.from_changes([
      shared_change.SchemaChange(schema.EmptySchema, schema.EmptySchema, False),
    ])
  let commit = history.Commit(revision_a(), local_session(), outer)
  let assert Ok(update) =
    history.append_local(history.new(local_session()), commit)

  shared_change.identity_revisions(commit.change) |> expect.to_equal([])
  shared_change.max_local_id(commit.change) |> expect.to_equal(-1)
  history.identity_revisions(update.history) |> expect.to_equal([revision_a()])
  history.pending(update.history) |> expect.to_equal([commit])
  update.effects
  |> expect.to_equal([
    shared_change.SchemaDelta(schema.EmptySchema, schema.EmptySchema, False),
  ])
}

pub fn shared_tree_history_ack_does_not_apply_twice_test() -> Nil {
  let #(commit, initial_forest) = real_commit()
  let assert Ok(local) =
    history.append_local(history.new(local_session()), commit)
  let assert [shared_change.DataDelta(delta)] = local.effects
  let assert Ok(optimistic_forest) = forest.apply_delta(initial_forest, delta)
  history.pending(local.history) |> expect.to_equal([commit])

  let assert Ok(#(ack, Nil)) =
    history.receive(
      local.history,
      commit,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  history.pending(ack.history) |> expect.to_equal([])
  ack.effects |> expect.to_equal([])
  forest.export_data(optimistic_forest)
  |> expect.to_equal(forest.export_data(optimistic_forest))
}

pub fn shared_tree_history_ack_advances_sequenced_forest_test() -> Nil {
  let #(commit, initial_forest) = real_commit()
  let assert Ok(local) =
    history.append_local(history.new(local_session()), commit)
  let assert [shared_change.DataDelta(local_delta)] = local.effects
  let assert Ok(optimistic) = forest.apply_delta(initial_forest, local_delta)
  let assert Ok(#(ack, Nil)) =
    history.receive(
      local.history,
      commit,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  ack.effects |> expect.to_equal([])
  let assert [shared_change.DataDelta(sequenced_delta)] = ack.sequenced_effects
  let assert Ok(sequenced) = forest.apply_delta(initial_forest, sequenced_delta)
  forest.export_data(sequenced)
  |> expect.to_equal(forest.export_data(optimistic))
}

pub fn shared_tree_history_local_contract_refusals_test() -> Nil {
  let first = empty_commit(revision_a(), local_session())
  let second = empty_commit(revision_b(), local_session())
  let peer = empty_commit(revision_b(), peer_session())
  let state = history.new(local_session())
  history.append_local(state, peer) |> expect.to_be_error
  let assert Ok(first_update) = history.append_local(state, first)
  history.append_local(first_update.history, first) |> expect.to_be_error
  let assert Ok(second_update) =
    history.append_local(first_update.history, second)
  let assert Error(InvalidHistory(_)) =
    history.receive(
      second_update.history,
      second,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  history.pending(second_update.history)
  |> expect.to_equal([first, second])
  let assert Error(InvalidHistory(_)) =
    history.receive(
      second_update.history,
      first,
      types.SequencePoint(1, -1),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Error(InvalidHistory(_)) =
    history.receive(
      second_update.history,
      first,
      types.SequencePoint(9_007_199_254_740_991 + 1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  Nil
}

pub fn shared_tree_history_retained_duplicate_does_not_ack_next_test() -> Nil {
  let first = empty_commit(revision_a(), local_session())
  let second = empty_commit(revision_b(), local_session())
  let assert Ok(first_update) =
    history.append_local(history.new(local_session()), first)
  let assert Ok(#(acked, Nil)) =
    history.receive(
      first_update.history,
      first,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(second_update) = history.append_local(acked.history, second)
  let assert Ok(#(duplicate, Nil)) =
    history.receive(
      second_update.history,
      first,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  history.pending(duplicate.history) |> expect.to_equal([second])
  duplicate.effects |> expect.to_equal([])
  duplicate.sequenced_effects |> expect.to_equal([])
}

pub fn shared_tree_history_retained_duplicate_rejects_conflicts_test() -> Nil {
  let first = empty_commit(revision_a(), local_session())
  let assert Ok(first_update) =
    history.append_local(history.new(local_session()), first)
  let assert Ok(#(acked, Nil)) =
    history.receive(
      first_update.history,
      first,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let changed = peer_edit(9.0)
  let conflicting_change =
    history.Commit(first.revision, first.originator, changed.change)
  history.receive(
    acked.history,
    conflicting_change,
    types.SequencePoint(1, 0),
    0,
    0,
    Nil,
    no_mint,
  )
  |> expect.to_be_error
  history.receive(
    acked.history,
    first,
    types.SequencePoint(1, 0),
    1,
    0,
    Nil,
    no_mint,
  )
  |> expect.to_be_error
  history.receive(
    acked.history,
    history.Commit(..first, originator: peer_session()),
    types.SequencePoint(1, 0),
    0,
    0,
    Nil,
    no_mint,
  )
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_history_retained_duplicate_preserves_advanced_minimum_test() -> Nil {
  let first = empty_commit(revision_a(), local_session())
  let second = empty_commit(revision_b(), local_session())
  let assert Ok(local) =
    history.append_local(history.new(local_session()), first)
  let assert Ok(#(acked, Nil)) =
    history.receive(
      local.history,
      first,
      types.SequencePoint(3, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(advanced, Nil)) =
    history.advance_minimum(acked.history, 5, 1, Nil, no_mint)
  let assert Ok(pending) = history.append_local(advanced.history, second)
  let before = history.inspect(pending.history)
  let assert Ok(#(replayed, Nil)) =
    history.receive(
      pending.history,
      first,
      types.SequencePoint(3, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  history.inspect(replayed.history) |> expect.to_equal(before)
  replayed.effects |> expect.to_equal([])
  history.receive(
    pending.history,
    second,
    types.SequencePoint(6, 0),
    5,
    0,
    Nil,
    no_mint,
  )
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_history_rebased_ack_replay_does_not_ack_next_test() -> Nil {
  let #(local, remote, _, allocation) = conflicting_commits()
  let assert Ok(local_update) =
    history.append_local(history.new(local_session()), local)
  let assert Ok(#(remote_update, allocation)) =
    history.receive(
      local_update.history,
      remote,
      types.SequencePoint(1, 0),
      0,
      0,
      allocation,
      mint,
    )
  let assert Ok(#(acked, allocation)) =
    history.receive(
      remote_update.history,
      local,
      types.SequencePoint(2, 0),
      1,
      0,
      allocation,
      mint,
    )
  let next =
    empty_commit(
      revision("00000000-0000-4000-8000-00000000000d"),
      local_session(),
    )
  let assert Ok(pending) = history.append_local(acked.history, next)
  let assert Ok(#(duplicate, _)) =
    history.receive(
      pending.history,
      local,
      types.SequencePoint(2, 0),
      1,
      0,
      allocation,
      mint,
    )
  history.pending(duplicate.history) |> expect.to_equal([next])
  duplicate.effects |> expect.to_equal([])
}

pub fn shared_tree_history_later_replay_snapshot_restores_test() -> Nil {
  let first = empty_commit(revision_a(), local_session())
  let assert Ok(local) =
    history.append_local(history.new(local_session()), first)
  let assert Ok(#(acked, Nil)) =
    history.receive(
      local.history,
      first,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(replayed, Nil)) =
    history.receive(
      acked.history,
      first,
      types.SequencePoint(2, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(snapshot) = history.snapshot(replayed.history)

  snapshot.trunk |> list.length |> expect.to_equal(2)
  history.restore(snapshot, local_session()) |> expect.to_be_ok
  Nil
}

pub fn shared_tree_history_restored_snapshot_authenticates_later_replay_test() -> Nil {
  let commit = empty_commit(revision_a(), local_session())
  let assert Ok(local) =
    history.append_local(history.new(local_session()), commit)
  let assert Ok(#(acked, Nil)) =
    history.receive(
      local.history,
      commit,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(snapshot) = history.snapshot(acked.history)
  let assert Ok(restored) = history.restore(snapshot, local_session())
  let assert Ok(#(replayed, Nil)) =
    history.receive(
      restored,
      commit,
      types.SequencePoint(2, 0),
      1,
      0,
      Nil,
      no_mint,
    )

  history.inspect(replayed.history).sequenced.trunk
  |> list.length
  |> expect.to_equal(2)
}

pub fn shared_tree_history_replay_retains_muted_trunk_content_test() -> Nil {
  let base = stored_schema()
  let assert Ok(optional) = schema.stored_from_string(optional_schema)
  let assert Ok(score) = schema.stored_from_string(score_schema)
  let competing = schema_commit(revision_a(), peer_session(), base, optional)
  let replayed = schema_commit(revision_b(), other_peer_session(), base, score)
  let assert Ok(order) =
    change.identity_order([
      #(revision_a(), -3),
      #(revision_b(), -2),
      #(revision_r(), -1),
    ])
  let allocation = Allocation([revision_r()], order, 0)
  let assert Ok(#(first, allocation)) =
    history.receive(
      history.new(local_session()),
      competing,
      types.SequencePoint(1, 0),
      0,
      0,
      allocation,
      mint,
    )
  let assert Ok(#(muted, allocation)) =
    history.receive(
      first.history,
      replayed,
      types.SequencePoint(2, 0),
      0,
      0,
      allocation,
      mint,
    )
  let assert [_, retained] = history.inspect(muted.history).sequenced.trunk
  shared_change.to_changes(retained.commit.change) |> expect.to_equal([])

  let assert Ok(#(duplicate, _)) =
    history.receive(
      muted.history,
      replayed,
      types.SequencePoint(3, 0),
      2,
      0,
      allocation,
      mint,
    )
  let assert Ok(snapshot) = history.snapshot(duplicate.history)
  let assert [_, first_replay, second_replay] = snapshot.trunk
  first_replay.commit.change |> expect.to_equal(second_replay.commit.change)
  history.restore(snapshot, local_session()) |> expect.to_be_ok
  Nil
}

pub fn shared_tree_history_restore_authenticates_muted_schema_replay_test() -> Nil {
  let base = stored_schema()
  let assert Ok(optional) = schema.stored_from_string(optional_schema)
  let assert Ok(score) = schema.stored_from_string(score_schema)
  let competing = schema_commit(revision_a(), peer_session(), base, optional)
  let replayed = schema_commit(revision_b(), other_peer_session(), base, score)
  let assert Ok(order) =
    change.identity_order([
      #(revision_a(), -3),
      #(revision_b(), -2),
      #(revision_r(), -1),
    ])
  let allocation = Allocation([revision_r()], order, 0)
  let assert Ok(#(first, allocation)) =
    history.receive(
      history.new(local_session()),
      competing,
      types.SequencePoint(1, 0),
      0,
      0,
      allocation,
      mint,
    )
  let assert Ok(#(muted, allocation)) =
    history.receive(
      first.history,
      replayed,
      types.SequencePoint(2, 0),
      0,
      0,
      allocation,
      mint,
    )
  let assert Ok(snapshot) = history.snapshot(muted.history)
  let assert Ok(restored) = history.restore(snapshot, local_session())

  history.receive(
    restored,
    replayed,
    types.SequencePoint(3, 0),
    2,
    0,
    allocation,
    mint,
  )
  |> expect.to_be_ok
  Nil
}

pub fn shared_tree_history_rebases_pending_over_remote_test() -> Nil {
  let #(local, remote, initial_forest, allocation) = conflicting_commits()
  let assert Ok(local_update) =
    history.append_local(history.new(local_session()), local)
  let assert [shared_change.DataDelta(local_delta)] = local_update.effects
  let assert Ok(optimistic) = forest.apply_delta(initial_forest, local_delta)
  let remote_result =
    history.receive(
      local_update.history,
      remote,
      types.SequencePoint(1, 0),
      0,
      0,
      allocation,
      mint,
    )
  remote_result |> expect.to_be_ok
  let assert Ok(#(remote_update, allocation)) = remote_result
  allocation.consumed |> expect.to_equal(1)
  let assert [shared_change.DataDelta(remote_delta)] = remote_update.effects
  let assert Ok(reconciled) = forest.apply_delta(optimistic, remote_delta)
  let view = history.inspect(remote_update.history)
  view.sequenced.trunk
  |> list.length
  |> expect.to_equal(1)
  history.pending(remote_update.history)
  |> list.length
  |> expect.to_equal(1)

  let assert Ok(#(ack, allocation)) =
    history.receive(
      remote_update.history,
      local,
      types.SequencePoint(2, 0),
      1,
      0,
      allocation,
      mint,
    )
  ack.effects |> expect.to_equal([])
  allocation.consumed |> expect.to_equal(1)
  forest.export_data(reconciled)
  |> expect.to_equal(forest.export_data(reconciled))
}

pub fn shared_tree_history_remote_exposes_rebased_trunk_delta_test() -> Nil {
  let #(local, remote, initial_forest, allocation) = conflicting_commits()
  let assert Ok(pending) =
    history.append_local(history.new(local_session()), local)
  let assert Ok(#(received, _)) =
    history.receive(
      pending.history,
      remote,
      types.SequencePoint(1, 0),
      0,
      0,
      allocation,
      mint,
    )
  let assert [shared_change.DataDelta(delta)] = received.sequenced_effects
  let assert Ok(sequenced) = forest.apply_delta(initial_forest, delta)
  forest.read(sequenced, ["point", "x"])
  |> expect.to_equal(Ok(Some(NumberValue(8.0))))
}

pub fn shared_tree_history_remote_failure_is_atomic_test() -> Nil {
  let #(local, remote, _, _) = conflicting_commits()
  let assert Ok(local_update) =
    history.append_local(history.new(local_session()), local)
  let before = history.inspect(local_update.history)
  let assert Error(InvalidHistory(_)) =
    history.receive(
      local_update.history,
      remote,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  history.inspect(local_update.history) |> expect.to_equal(before)
}

pub fn shared_tree_history_snapshot_refuses_pending_test() -> Nil {
  let commit = empty_commit(revision_a(), local_session())
  let assert Ok(local) =
    history.append_local(history.new(local_session()), commit)
  history.snapshot(local.history) |> expect.to_be_error
  history.pending(local.history) |> expect.to_equal([commit])
}

pub fn shared_tree_history_restore_rejects_missing_peer_base_test() -> Nil {
  let invalid =
    history.HistorySnapshot(
      history.InitialBase,
      [],
      [history.PeerBranch(peer_session(), Some(revision_a()), [])],
      0,
      -9_007_199_254_740_991,
    )
  history.restore(invalid, local_session()) |> expect.to_be_error
  Nil
}

pub fn shared_tree_history_restore_allows_divergent_revision_copy_test() -> Nil {
  let trunk = peer_edit(7.0)
  let authored = peer_edit(8.0)
  let snapshot =
    history.HistorySnapshot(
      history.InitialBase,
      [history.SequencedCommit(trunk, types.SequencePoint(1, 0))],
      [history.PeerBranch(peer_session(), None, [authored])],
      1,
      -9_007_199_254_740_991,
    )
  history.restore(snapshot, local_session()) |> expect.to_be_ok
  Nil
}

pub fn shared_tree_history_restore_rejects_conflicting_trunk_revision_test() -> Nil {
  let commit = peer_edit(7.0)
  let conflicting = peer_edit(8.0)
  let snapshot =
    history.HistorySnapshot(
      history.InitialBase,
      [
        history.SequencedCommit(commit, types.SequencePoint(1, 0)),
        history.SequencedCommit(conflicting, types.SequencePoint(2, 0)),
      ],
      [],
      2,
      -9_007_199_254_740_991,
    )
  history.restore(snapshot, local_session()) |> expect.to_be_error
  Nil
}

pub fn shared_tree_history_restore_rejects_conflicting_revision_origin_test() -> Nil {
  let trunk = peer_edit(7.0)
  let other_session = session("00000000-0000-4000-8000-000000000003")
  let peer = history.Commit(..peer_edit(8.0), originator: other_session)
  let snapshot =
    history.HistorySnapshot(
      history.InitialBase,
      [history.SequencedCommit(trunk, types.SequencePoint(1, 0))],
      [history.PeerBranch(other_session, None, [peer])],
      1,
      -9_007_199_254_740_991,
    )
  history.restore(snapshot, local_session()) |> expect.to_be_error
  Nil
}

pub fn shared_tree_history_rejects_receive_behind_processed_watermark_test() -> Nil {
  let assert Ok(#(advanced, Nil)) =
    history.advance_minimum(history.new(local_session()), 10, 5, Nil, no_mint)
  let remote = empty_commit(revision_b(), peer_session())
  history.receive(
    advanced.history,
    remote,
    types.SequencePoint(6, 0),
    5,
    5,
    Nil,
    no_mint,
  )
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_history_rejects_reused_trimmed_sequence_point_test() -> Nil {
  let first = empty_commit(revision_b(), peer_session())
  let assert Ok(#(received, Nil)) =
    history.receive(
      history.new(local_session()),
      first,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(trimmed, Nil)) =
    history.advance_minimum(received.history, 10, 1, Nil, no_mint)
  let next = empty_commit(revision_r(), peer_session())
  history.receive(
    trimmed.history,
    next,
    types.SequencePoint(1, 1),
    1,
    1,
    Nil,
    no_mint,
  )
  |> expect.to_be_error
  Nil
}

pub fn shared_tree_history_allows_same_sequence_continuation_and_gaps_test() -> Nil {
  let first = empty_commit(revision_b(), peer_session())
  let second = empty_commit(revision_r(), peer_session())
  let assert Ok(#(received, Nil)) =
    history.receive(
      history.new(local_session()),
      first,
      types.SequencePoint(5, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(continued, Nil)) =
    history.receive(
      received.history,
      second,
      types.SequencePoint(5, 1),
      0,
      0,
      Nil,
      no_mint,
    )
  let gap =
    empty_commit(
      revision("00000000-0000-4000-8000-00000000000d"),
      peer_session(),
    )
  history.receive(
    continued.history,
    gap,
    types.SequencePoint(9, 0),
    5,
    0,
    Nil,
    no_mint,
  )
  |> expect.to_be_ok
  Nil
}

pub fn shared_tree_history_trim_rejects_unavailable_reference_test() -> Nil {
  let first = empty_commit(revision_b(), peer_session())
  let assert Ok(#(received, Nil)) =
    history.receive(
      history.new(local_session()),
      first,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  let assert Ok(#(trimmed, Nil)) =
    history.advance_minimum(received.history, 1, 1, Nil, no_mint)
  trimmed.trimmed_revisions |> expect.to_equal([revision_b()])
  let before = history.inspect(trimmed.history)
  let stale = empty_commit(revision_r(), peer_session())
  let assert Error(InvalidHistory(_)) =
    history.receive(
      trimmed.history,
      stale,
      types.SequencePoint(2, 0),
      0,
      1,
      Nil,
      no_mint,
    )
  history.inspect(trimmed.history) |> expect.to_equal(before)
}

pub fn shared_tree_history_resubmit_is_pure_and_stable_test() -> Nil {
  let commit = empty_commit(revision_a(), local_session())
  let assert Ok(local) =
    history.append_local(history.new(local_session()), commit)
  history.resubmit(local.history, []) |> expect.to_equal(Ok([commit]))
  history.resubmit(local.history, []) |> expect.to_equal(Ok([commit]))

  let extraneous =
    forest.Build(types.AtomId(Some(revision_a()), 0), [point(1.0, 2.0)])
  history.resubmit(local.history, [#(revision_a(), [extraneous])])
  |> expect.to_be_error

  let assert Ok(#(acked, Nil)) =
    history.receive(
      local.history,
      commit,
      types.SequencePoint(1, 0),
      0,
      0,
      Nil,
      no_mint,
    )
  history.resubmit(acked.history, []) |> expect.to_equal(Ok([]))
}
