//// Independent causal model for outer keys and per-key string members.
////
//// Expected dots come from an independent local cursor and captured intent.
//// Expected membership is a union of additions minus observed retractions.
//// Native codecs are used only to observe the implementation and save deltas.
//// Authoring cursors are checked locally, not compared between replicas.

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import lattice_core/replica_id
import lattice_maps/or_map
import qcheck
import watershed/canonical_json
import watershed/fuzz/kernel_fuzz.{
  type KernelModel, type LogEntry, Capabilities, KernelModel,
}
import watershed/fuzz/or_map_metadata.{type Generation}
import watershed/or_map_kernel as kernel
import watershed/or_map_set_leaf

type ORMapDelta =
  or_map.ORMapDelta(String)

pub type Dot =
  #(String, Int)

pub type SetObservation {
  SetObservation(entries: List(#(String, List(Dot))), tombstones: List(Dot))
}

pub type Observation {
  Observation(
    keys: SetObservation,
    members: List(#(String, SetObservation)),
    bounds: List(#(String, List(#(String, Int)))),
    visible: List(#(String, List(String))),
    generations: List(#(String, Generation)),
  )
}

pub type Intent {
  AddMember
  RemoveMember
  RemoveKey
}

pub type Context {
  Context(
    reference_sequence_number: Int,
    author: String,
    counter: Int,
    key_dots: List(Dot),
    members: Option(SetObservation),
    removal_bound: List(#(String, Int)),
    generation: Generation,
  )
}

pub type SetMapCommand {
  SetMapCommand(
    intent: Intent,
    key: String,
    member: String,
    context: Option(Context),
    delta: Option(ORMapDelta),
  )
}

pub fn empty_observation() -> Observation {
  Observation(SetObservation([], []), [], [], [], [])
}

fn compare_dot(left: Dot, right: Dot) -> order.Order {
  case canonical_json.compare(left.0, right.0) {
    order.Eq -> int.compare(left.1, right.1)
    other -> other
  }
}

fn sorted_pairs(pairs: List(#(String, a))) -> List(#(String, a)) {
  list.sort(pairs, fn(left, right) { canonical_json.compare(left.0, right.0) })
}

fn dots(dots: List(Dot)) -> List(Dot) {
  dots |> list.unique |> list.sort(compare_dot)
}

fn get(pairs: List(#(String, a)), key: String, default: a) -> a {
  pairs |> dict.from_list |> dict.get(key) |> result.unwrap(default)
}

fn normalize_set(state: SetObservation) -> SetObservation {
  let tombstones = dots(state.tombstones)
  let entries =
    state.entries
    |> sorted_pairs
    |> list.filter_map(fn(pair) {
      let live =
        pair.1
        |> list.filter(fn(dot) { !list.contains(tombstones, dot) })
        |> dots
      case live {
        [] -> Error(Nil)
        _ -> Ok(#(pair.0, live))
      }
    })
  SetObservation(entries, tombstones)
}

fn join_set(left: SetObservation, right: SetObservation) -> SetObservation {
  let entries =
    dict.combine(
      dict.from_list(left.entries),
      dict.from_list(right.entries),
      list.append,
    )
    |> dict.to_list
  normalize_set(SetObservation(
    entries,
    list.append(left.tombstones, right.tombstones),
  ))
}

fn retract(state: SetObservation, removed: List(Dot)) -> SetObservation {
  normalize_set(
    SetObservation(..state, tombstones: list.append(state.tombstones, removed)),
  )
}

fn live_dots(state: SetObservation) -> List(Dot) {
  state.entries |> list.flat_map(fn(pair) { pair.1 })
}

fn join_bound(
  left: List(#(String, Int)),
  right: List(#(String, Int)),
) -> List(#(String, Int)) {
  dict.combine(dict.from_list(left), dict.from_list(right), int.max)
  |> dict.to_list
  |> sorted_pairs
}

fn bound(dots: List(Dot)) -> List(#(String, Int)) {
  list.fold(dots, [], fn(acc, dot) { join_bound(acc, [dot]) })
}

fn visible(observation: Observation) -> List(#(String, List(String))) {
  observation.keys.entries
  |> list.map(fn(pair) {
    let leaf = get(observation.members, pair.0, SetObservation([], []))
    #(pair.0, list.map(leaf.entries, fn(member) { member.0 }))
  })
}

fn key_observation(state: Observation, key: String) -> Observation {
  let bounds = get(state.bounds, key, [])
  Observation(
    SetObservation(
      list.filter(state.keys.entries, fn(pair) { pair.0 == key }),
      list.filter(state.keys.tombstones, fn(dot) {
        dot.1 <= get(bounds, dot.0, 0)
      }),
    ),
    list.filter(state.members, fn(pair) { pair.0 == key }),
    list.filter(state.bounds, fn(pair) { pair.0 == key }),
    [],
    list.filter(state.generations, fn(pair) { pair.0 == key }),
  )
}

fn join(left: Observation, right: Observation) -> Observation {
  list.append(left.generations, right.generations)
  |> list.map(fn(pair) { pair.0 })
  |> list.unique
  |> list.fold(empty_observation(), fn(joined, key) {
    let a = key_observation(left, key)
    let b = key_observation(right, key)
    let selected = case
      or_map_metadata.compare(
        get(left.generations, key, #(0, None)),
        get(right.generations, key, #(0, None)),
      )
    {
      order.Gt -> a
      order.Lt -> b
      order.Eq -> join_same_generation(a, b)
    }
    join_same_generation(joined, selected)
  })
}

fn join_same_generation(left: Observation, right: Observation) -> Observation {
  let joined =
    Observation(
      join_set(left.keys, right.keys),
      dict.combine(
        dict.from_list(left.members),
        dict.from_list(right.members),
        join_set,
      )
        |> dict.to_list
        |> sorted_pairs,
      dict.combine(
        dict.from_list(left.bounds),
        dict.from_list(right.bounds),
        join_bound,
      )
        |> dict.to_list
        |> sorted_pairs,
      [],
      list.append(left.generations, right.generations)
        |> list.unique
        |> sorted_pairs,
    )
  Observation(..joined, visible: visible(joined))
}

fn changes(command: SetMapCommand, context: Context) -> Bool {
  case command.intent {
    AddMember -> True
    RemoveKey -> !list.is_empty(context.key_dots)
    RemoveMember ->
      !list.is_empty(context.key_dots)
      && case context.members {
        None -> False
        Some(leaf) -> !list.is_empty(get(leaf.entries, command.member, []))
      }
  }
}

/// A contribution includes only the key delta and the captured leaf payload.
/// A later receiver's knowledge cannot change what this operation removes.
pub fn contribution(command: SetMapCommand) -> Observation {
  let assert Some(context) = command.context
  case changes(command, context) {
    False -> empty_observation()
    True -> {
      let dot = #(context.author, context.counter)
      let key_dot = #(
        or_map_metadata.membership_author(
          context.author,
          command.key,
          context.generation,
        ),
        context.counter,
      )
      let leaf = option.unwrap(context.members, SetObservation([], []))
      let leaf = case context.key_dots {
        [] -> retract(leaf, live_dots(leaf))
        _ -> leaf
      }
      let #(keys, leaf, bounds) = case command.intent {
        AddMember -> #(
          SetObservation([#(command.key, [key_dot])], []),
          join_set(leaf, SetObservation([#(command.member, [dot])], [])),
          [],
        )
        RemoveMember -> #(
          SetObservation([#(command.key, [key_dot])], []),
          retract(leaf, get(leaf.entries, command.member, [])),
          [],
        )
        RemoveKey -> {
          let removed_keys = dots([key_dot, ..context.key_dots])
          #(SetObservation([], removed_keys), retract(leaf, live_dots(leaf)), [
            #(command.key, bound(removed_keys)),
          ])
        }
      }
      let observation =
        Observation(keys, [#(command.key, leaf)], bounds, [], [
          #(command.key, context.generation),
        ])
      Observation(..observation, visible: visible(observation))
    }
  }
}

pub fn oracle(entries: List(LogEntry(SetMapCommand))) -> Observation {
  kernel_fuzz.log_operations(entries)
  |> list.fold(empty_observation(), fn(state, entry) {
    join(state, contribution(entry.1))
  })
}

pub type State {
  State(
    actual: kernel.OrMapState,
    author: String,
    confirmed: Observation,
    pending: List(SetMapCommand),
    floor: Int,
    member_floors: Dict(String, Int),
  )
}

fn author(id: Int) -> String {
  "client-" <> int.to_string(id)
}

fn expected(state: State) -> Observation {
  list.fold(state.pending, state.confirmed, fn(acc, command) {
    join(acc, contribution(command))
  })
}

fn capture(
  state: State,
  command: SetMapCommand,
  meta: kernel_fuzz.SubmitMeta,
) -> SetMapCommand {
  let observation = expected(state)
  let context =
    Context(
      meta.last_seen_sequence_number,
      state.author,
      state.floor,
      get(observation.keys.entries, command.key, []),
      observation.members
        |> dict.from_list
        |> dict.get(command.key)
        |> option.from_result,
      get(observation.bounds, command.key, []),
      get(observation.generations, command.key, #(0, None)),
    )
  let counter = case changes(command, context) {
    True -> state.floor + 1
    False -> state.floor
  }
  let generation = case command.intent, context.key_dots {
    AddMember, [] ->
      case list.key_find(observation.generations, command.key) {
        Ok(_) -> #(counter, Some(state.author))
        Error(Nil) -> #(0, None)
      }
    _, _ -> context.generation
  }
  SetMapCommand(
    ..command,
    context: Some(Context(..context, counter: counter, generation: generation)),
    delta: None,
  )
}

fn reserve(state: State, command: SetMapCommand) -> State {
  let assert Some(context) = command.context
  case changes(command, context) {
    False -> state
    True -> {
      let leaf_counter = case command.intent {
        AddMember -> context.counter
        RemoveMember | RemoveKey -> context.counter - 1
      }
      State(
        ..state,
        floor: int.max(state.floor, context.counter),
        member_floors: dict.insert(
          state.member_floors,
          command.key,
          int.max(
            result.unwrap(dict.get(state.member_floors, command.key), 0),
            leaf_counter,
          ),
        ),
      )
    }
  }
}

pub fn operation(command: SetMapCommand) -> kernel.OrMapOperation {
  let assert Some(delta) = command.delta
  case command.intent {
    AddMember -> kernel.AddMember(command.key, command.member, delta)
    RemoveMember -> kernel.RemoveMember(command.key, command.member, delta)
    RemoveKey -> kernel.Remove(command.key, delta)
  }
}

fn delta(operation: kernel.OrMapOperation) -> ORMapDelta {
  case operation {
    kernel.AddMember(_, _, delta)
    | kernel.RemoveMember(_, _, delta)
    | kernel.Remove(_, delta) -> delta
    kernel.Increment(_, _, _)
    | kernel.SetRegister(_, _, _, _)
    | kernel.SetMvRegister(_, _, _) -> panic as "Unexpected non-set operation."
  }
}

fn submit(
  state: State,
  command: SetMapCommand,
  meta: kernel_fuzz.SubmitMeta,
) -> #(State, Option(SetMapCommand)) {
  let captured = capture(state, command, meta)
  let result = case command.intent {
    AddMember -> kernel.add_member(state.actual, command.key, command.member)
    RemoveMember ->
      kernel.remove_member(state.actual, command.key, command.member)
    RemoveKey -> kernel.remove(state.actual, command.key)
  }
  let assert Ok(#(actual, _, operation, _)) = result
  let routed = SetMapCommand(..captured, delta: Some(delta(operation)))
  #(
    reserve(
      State(
        ..state,
        actual: actual,
        pending: list.append(state.pending, [routed]),
      ),
      routed,
    ),
    Some(routed),
  )
}

fn apply_remote(
  state: State,
  command: SetMapCommand,
  _meta: kernel_fuzz.SequencedMeta,
) -> Result(State, String) {
  use #(actual, _) <- result.try(
    kernel.apply_remote(state.actual, operation(command))
    |> result.map_error(string.inspect),
  )
  Ok(reserve(
    State(
      ..state,
      actual: actual,
      confirmed: join(state.confirmed, contribution(command)),
    ),
    command,
  ))
}

fn ack_local(
  state: State,
  command: SetMapCommand,
  _meta: kernel_fuzz.SequencedMeta,
) -> Result(State, String) {
  use actual <- result.try(
    kernel.ack_local(state.actual, operation(command))
    |> result.map_error(string.inspect),
  )
  let assert [first, ..pending] = state.pending
  let assert True = first == command
  Ok(reserve(
    State(
      ..state,
      actual: actual,
      confirmed: join(state.confirmed, contribution(command)),
      pending: pending,
    ),
    command,
  ))
}

fn rollback(state: State, command: SetMapCommand) -> State {
  let assert Ok(pending) = list.last(state.actual.pending)
  let assert Ok(#(actual, _)) =
    kernel.rollback(state.actual, operation(command), pending.message_id)
  State(
    ..state,
    actual: actual,
    pending: list.take(state.pending, list.length(state.pending) - 1),
  )
}

fn apply_stashed(
  state: State,
  command: SetMapCommand,
  _meta: kernel_fuzz.SubmitMeta,
) -> #(State, SetMapCommand) {
  let assert Some(_) = command.context
  let assert Ok(#(actual, _, returned, _)) =
    kernel.apply_stashed_operation(state.actual, operation(command))
  let assert True = returned == operation(command)
  #(
    reserve(
      State(
        ..state,
        actual: actual,
        pending: list.append(state.pending, [command]),
      ),
      command,
    ),
    command,
  )
}

fn dot_decoder() -> decode.Decoder(Dot) {
  use author <- decode.field("r", decode.string)
  use counter <- decode.field("c", decode.int)
  decode.success(#(author, counter))
}

fn set_decoder() -> decode.Decoder(SetObservation) {
  use entries <- decode.field(
    "entries",
    decode.dict(decode.string, decode.list(dot_decoder())),
  )
  use tombstones <- decode.field("tombstones", decode.list(dot_decoder()))
  decode.success(SetObservation(
    entries
      |> dict.to_list
      |> sorted_pairs
      |> list.map(fn(pair) { #(pair.0, dots(pair.1)) }),
    dots(tombstones),
  ))
}

fn native_set_decoder() -> decode.Decoder(#(SetObservation, Int)) {
  decode.at(["state"], {
    use counter <- decode.field("counter", decode.int)
    use pruned <- decode.field(
      "pruned",
      decode.at(["state", "clocks"], decode.dict(decode.string, decode.int)),
    )
    use entries <- decode.field(
      "entries",
      decode.list({
        use value <- decode.field("value", decode.string)
        use tags <- decode.field("tags", decode.list(dot_decoder()))
        decode.success(#(value, dots(tags)))
      }),
    )
    use tombstones <- decode.field("tombstones", decode.list(dot_decoder()))
    let observation = SetObservation(sorted_pairs(entries), dots(tombstones))
    case dict.size(pruned) {
      0 -> decode.success(#(observation, counter))
      _ -> decode.failure(#(observation, counter), "Unpruned set metadata")
    }
  })
}

fn native_observation(
  map: or_map.ORMap(String),
) -> Result(#(Observation, Int, Dict(String, Int)), String) {
  let encoded = or_map.to_json(map) |> json.to_string
  use entries <- result.try(
    json.parse(encoded, or_map_metadata.entries_decoder())
    |> result.map_error(string.inspect),
  )
  use counter <- result.try(
    json.parse(encoded, decode.at(["state", "clock"], decode.int))
    |> result.map_error(string.inspect),
  )
  list.try_fold(
    entries,
    #(empty_observation(), counter, dict.new()),
    fn(acc, entry) {
      use #(membership, key_counter) <- result.try(
        json.parse(entry.membership, native_set_decoder())
        |> result.map_error(string.inspect),
      )
      use leaf <- result.try(case entry.value {
        None -> Ok(None)
        Some(encoded) ->
          json.parse(encoded, native_set_decoder())
          |> result.map(Some)
          |> result.map_error(string.inspect)
      })
      let observation =
        Observation(
          membership,
          case leaf {
            None -> []
            Some(leaf) -> [#(entry.key, leaf.0)]
          },
          case membership.tombstones {
            [] -> []
            removed -> [#(entry.key, bound(removed))]
          },
          [],
          [#(entry.key, entry.generation)],
        )
      Ok(
        #(
          join_same_generation(acc.0, observation),
          int.max(acc.1, key_counter),
          case leaf {
            None -> acc.2
            Some(leaf) -> dict.insert(acc.2, entry.key, leaf.1)
          },
        ),
      )
    },
  )
}

pub fn observe(state: State) -> Observation {
  let assert Ok(#(observation, _, _)) =
    native_observation(state.actual.optimistic)
  let visible =
    kernel.entries(state.actual)
    |> list.map(fn(pair) {
      let assert kernel.SetMembers(members) = pair.1
      #(pair.0, members)
    })
  Observation(..observation, visible: visible)
}

fn require(condition: Bool, detail: String) -> Result(Nil, String) {
  case condition {
    True -> Ok(Nil)
    False -> Error(detail)
  }
}

pub fn check(state: State) -> Result(Nil, String) {
  use _ <- result.try(kernel.check_cache_coherence(state.actual))
  use #(confirmed, checkpoint_counter, _) <- result.try(native_observation(
    state.actual.sequenced,
  ))
  use #(_, optimistic_counter, _) <- result.try(native_observation(
    state.actual.optimistic,
  ))
  use _ <- result.try(require(
    state.actual.set_clocks.key_counter >= state.floor
      && checkpoint_counter >= state.floor
      && optimistic_counter >= state.floor,
    "Counter floor rewound below issued or observed dots.",
  ))
  use _ <- result.try(require(
    list.all(dict.to_list(state.member_floors), fn(pair) {
      result.unwrap(
        dict.get(state.actual.set_clocks.member_counters, pair.0),
        0,
      )
      >= pair.1
    }),
    "Member counter floor rewound.",
  ))
  use _ <- result.try(require(
    state.actual.set_clocks.key_counter <= 9_007_199_254_740_991
      && list.all(
      dict.values(state.actual.set_clocks.member_counters),
      fn(counter) { counter >= 0 && counter <= 9_007_199_254_740_991 },
    ),
    "Counter is not a safe integer.",
  ))
  use _ <- result.try(require(
    confirmed == state.confirmed,
    "Confirmed causal state differs from independent oracle: "
      <> string.inspect(confirmed)
      <> " != "
      <> string.inspect(state.confirmed),
  ))
  let wanted = expected(state)
  let observed = observe(state)
  require(
    observed == wanted,
    "Optimistic causal state differs from independent oracle: "
      <> string.inspect(observed)
      <> " != "
      <> string.inspect(wanted),
  )
}

fn load_from_synced(state: State, id: Int) -> State {
  let assert Ok(actual) =
    kernel.from_summary(
      kernel.summary(state.actual) |> json.to_string,
      replica_id.new(author(id)),
    )
  State(actual, author(id), state.confirmed, [], state.floor, dict.new())
}

fn set_to_json(state: SetObservation) -> json.Json {
  json.object([
    #(
      "entries",
      json.object(
        list.map(state.entries, fn(pair) {
          #(pair.0, json.array(pair.1, dot_to_json))
        }),
      ),
    ),
    #("tombstones", json.array(state.tombstones, dot_to_json)),
  ])
}

fn dot_to_json(dot: Dot) -> json.Json {
  json.object([#("r", json.string(dot.0)), #("c", json.int(dot.1))])
}

fn context_to_json(context: Context) -> json.Json {
  json.object([
    #("ref_seq", json.int(context.reference_sequence_number)),
    #("author", json.string(context.author)),
    #("counter", json.int(context.counter)),
    #("key_dots", json.array(context.key_dots, dot_to_json)),
    #("members", case context.members {
      None -> json.null()
      Some(members) -> set_to_json(members)
    }),
    #(
      "removal_bound",
      json.object(
        list.map(context.removal_bound, fn(pair) { #(pair.0, json.int(pair.1)) }),
      ),
    ),
    #("generation", or_map_metadata.generation_json(context.generation)),
  ])
}

fn context_decoder() -> decode.Decoder(Context) {
  use reference <- decode.field("ref_seq", decode.int)
  use author <- decode.field("author", decode.string)
  use counter <- decode.field("counter", decode.int)
  use keys <- decode.field("key_dots", decode.list(dot_decoder()))
  use members <- decode.field("members", decode.optional(set_decoder()))
  use bounds <- decode.field(
    "removal_bound",
    decode.dict(decode.string, decode.int),
  )
  use generation <- decode.field(
    "generation",
    or_map_metadata.generation_decoder(),
  )
  decode.success(Context(
    reference,
    author,
    counter,
    keys,
    members,
    bounds |> dict.to_list |> sorted_pairs,
    generation,
  ))
}

pub fn operation_to_json(command: SetMapCommand) -> json.Json {
  json.object([
    #(
      "tag",
      json.string(case command.intent {
        AddMember -> "AddMember"
        RemoveMember -> "RemoveMember"
        RemoveKey -> "RemoveKey"
      }),
    ),
    #("key", json.string(command.key)),
    #("member", json.string(command.member)),
    #("context", case command.context {
      None -> json.null()
      Some(context) -> context_to_json(context)
    }),
    #("delta", case command.delta {
      None -> json.null()
      Some(delta) ->
        or_map.delta_to_json(delta) |> json.to_string |> json.string
    }),
  ])
}

pub fn operation_decoder() -> decode.Decoder(SetMapCommand) {
  use tag <- decode.field("tag", decode.string)
  use key <- decode.field("key", decode.string)
  use member <- decode.field("member", decode.string)
  use context <- decode.field("context", decode.optional(context_decoder()))
  use encoded <- decode.field("delta", decode.optional(decode.string))
  let fallback = SetMapCommand(AddMember, key, member, None, None)
  let intent = case tag {
    "AddMember" -> Ok(AddMember)
    "RemoveMember" -> Ok(RemoveMember)
    "RemoveKey" -> Ok(RemoveKey)
    _ -> Error(Nil)
  }
  case intent, context, encoded {
    Ok(intent), None, None ->
      decode.success(SetMapCommand(intent, key, member, None, None))
    Ok(intent), Some(context), Some(encoded) ->
      case or_map_set_leaf.decode_delta(encoded) {
        Ok(delta) ->
          decode.success(SetMapCommand(
            intent,
            key,
            member,
            Some(context),
            Some(delta),
          ))
        Error(_) -> decode.failure(fallback, "Valid captured set-map delta")
      }
    _, _, _ -> decode.failure(fallback, "Intent and paired context/delta")
  }
}

fn small_string(number: Int) -> String {
  case number % 5 {
    0 -> ""
    1 -> "doc"
    2 -> "other"
    3 -> "\u{e000}"
    _ -> "\u{10000}"
  }
}

fn operation_generator() -> qcheck.Generator(SetMapCommand) {
  qcheck.tuple3(
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
  )
  |> qcheck.map(fn(values) {
    captured_generated_operation(values.0 % 8, values.1 % 5, values.2 % 5)
  })
}

fn new_state(author: String) -> State {
  State(
    kernel.new(replica_id.new(author), kernel.OrSetMode),
    author,
    empty_observation(),
    [],
    0,
    dict.new(),
  )
}

/// Materialize before script execution so dump_failure saves the original
/// context and native delta. Separate origins prevent reuse of active writers'
/// dots. Repeated generator inputs deliberately replay the same original.
fn captured_generated_operation(
  kind: Int,
  key_index: Int,
  member_index: Int,
) -> SetMapCommand {
  let intent = case kind % 4 {
    0 -> RemoveKey
    1 -> RemoveMember
    _ -> AddMember
  }
  let command =
    SetMapCommand(
      intent,
      small_string(key_index),
      small_string(member_index),
      None,
      None,
    )
  let origin =
    "stash-"
    <> int.to_string(kind)
    <> "-"
    <> int.to_string(key_index)
    <> "-"
    <> int.to_string(member_index)
  let meta = kernel_fuzz.SubmitMeta(0, 0)
  let state = new_state(origin)
  let state = case kind % 4 == 2 {
    True -> state
    False -> {
      let #(state, _) =
        submit(state, SetMapCommand(..command, intent: AddMember), meta)
      state
    }
  }
  let state = case kind >= 4 {
    False -> state
    True -> {
      let #(state, _) =
        submit(state, SetMapCommand(..command, intent: RemoveKey), meta)
      let #(state, _) =
        submit(state, SetMapCommand(..command, intent: AddMember), meta)
      state
    }
  }
  let #(_, original) = submit(state, command, meta)
  let assert Some(original) = original
  original
}

pub fn model() -> KernelModel(State, SetMapCommand, Observation) {
  KernelModel(
    name: "or_map_set",
    init: fn(id) { new_state(author(id)) },
    submit: submit,
    apply_remote: apply_remote,
    ack_local: ack_local,
    observe: observe,
    gen_operation: operation_generator(),
    check: Some(check),
    canonicalize: None,
    ack_preserves_view: True,
    operation_to_json: operation_to_json,
    operation_decoder: operation_decoder(),
    capabilities: Capabilities(
      load_from_synced: Some(load_from_synced),
      oracle: Some(oracle),
      rollback: Some(rollback),
      resubmit: None,
      apply_stashed: Some(apply_stashed),
      react: None,
      remove_member: None,
    ),
  )
}
