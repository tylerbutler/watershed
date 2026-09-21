import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import watershed/fluid_ids.{
  type Compressor, type CreationRange, type IdError, type SessionSpaceId,
}
import watershed/json_ot

type Schedule {
  Schedule(
    a: Compressor,
    b: Compressor,
    initial_a: List(SessionSpaceId),
    initial_b: List(SessionSpaceId),
    later_a: List(SessionSpaceId),
    later_b: List(SessionSpaceId),
    ranges: List(CreationRange),
    before: Json,
  )
}

type Trace {
  Trace(
    clients: Dict(Int, Compressor),
    ranges: List(CreationRange),
    observations: List(Json),
  )
}

pub fn run(input: Json) -> Result(Json, String) {
  use size <- result.try(read(input, ["clusterSize"], decode.int))
  use a <- result.try(read(input, ["sessions", "a"], decode.string))
  use b <- result.try(read(input, ["sessions", "b"], decode.string))
  use a <- result.try(create(a, size))
  use b <- result.try(create(b, size))
  use steps <- result.try(read(input, ["schedule"], decode.list(decode.string)))
  let state = Schedule(a, b, [], [], [], [], [], json.null())
  use state <- result.try(list.try_fold(steps, state, schedule_step))
  use after <- result.try(after_finalization(state))
  use last_a <- result.try(last(state.later_a))
  use last_b <- result.try(last(state.later_b))
  use a_to_b <- result.try(remote(state.a, state.b, last_a))
  use b_to_a <- result.try(remote(state.b, state.a, last_b))
  use ongoing <- result.try(read(
    input,
    ["operations", "restoration", "ongoing", "serialized"],
    decode.string,
  ))
  use ongoing_flag <- result.try(read(
    input,
    ["operations", "restoration", "ongoing", "includeLocalState"],
    decode.bool,
  ))
  use summary <- result.try(read(
    input,
    ["operations", "restoration", "summary", "serialized"],
    decode.string,
  ))
  use summary_flag <- result.try(read(
    input,
    ["operations", "restoration", "summary", "includeLocalState"],
    decode.bool,
  ))
  use summary_session <- result.try(read(
    input,
    ["operations", "restoration", "summary", "newSessionId"],
    decode.string,
  ))
  use summary_session <- result.try(
    native(fluid_ids.session_id(summary_session)),
  )
  use restored <- result.try(
    native(fluid_ids.deserialize(
      json.string(ongoing),
      fluid_ids.local_session(state.a),
    )),
  )
  use restored_summary <- result.try(
    native(fluid_ids.deserialize(json.string(summary), summary_session)),
  )
  use #(restored, next) <- result.try(native(fluid_ids.generate(restored)))
  use ongoing_next <- result.try(describe(restored, next))
  use #(restored_summary, next) <- result.try(
    native(fluid_ids.generate(restored_summary)),
  )
  use summary_next <- result.try(describe(restored_summary, next))
  use with_session <- result.try(
    native(fluid_ids.serialize(state.a, ongoing_flag)),
  )
  use summary_bytes <- result.try(
    native(fluid_ids.serialize(state.a, summary_flag)),
  )
  use ranges <- result.try(
    list.try_map(state.ranges, fn(range) {
      native(fluid_ids.creation_range_to_json(range))
    }),
  )
  use #(a, unique) <- result.try(native(fluid_ids.generate(state.a)))
  use unique_json <- result.try(
    case fluid_ids.session_space_id_to_int(unique) >= 0 {
      True -> Ok(json.int(fluid_ids.session_space_id_to_int(unique)))
      False -> {
        use stable <- result.try(native(fluid_ids.decompress(a, unique)))
        Ok(json.string(fluid_ids.stable_id_to_string(stable)))
      }
    },
  )
  use exact <- result.try(read(
    input,
    ["operations", "precision", "lastExactOffset"],
    decode.string,
  ))
  use rejected <- result.try(read(
    input,
    ["operations", "precision", "firstRejectedOffset"],
    decode.string,
  ))
  use exact <- result.try(precision(a, exact))
  use rejected <- result.try(precision(a, rejected))
  use malformed <- result.try(
    field(input, ["operations", "malformedAllocation"]),
  )
  use refusal <- result.try(malformed_allocation(malformed))
  use growth <- result.try(field(input, ["traces", "growth"]))
  use growth <- result.try(run_trace(growth))
  use carry <- result.try(field(input, ["traces", "uuidCarry"]))
  use carry <- result.try(run_trace(carry))
  use safe_integers <- result.try(field(input, ["traces", "safeIntegers"]))
  use safe_integers <- result.try(run_trace(safe_integers))
  Ok(
    json.object([
      #(
        "observations",
        array([
          stage("before-finalization", state.before),
          stage("after-finalization", after),
          stage(
            "remote-normalization",
            json.object([#("aToB", a_to_b), #("bToA", b_to_a)]),
          ),
          stage(
            "restoration",
            json.object([
              #(
                "ongoingSession",
                json.string(
                  fluid_ids.session_id_to_string(fluid_ids.local_session(
                    restored,
                  )),
                ),
              ),
              #("ongoingNext", ongoing_next),
              #(
                "summarySession",
                json.string(
                  fluid_ids.session_id_to_string(fluid_ids.local_session(
                    restored_summary,
                  )),
                ),
              ),
              #("summaryNext", summary_next),
            ]),
          ),
          stage(
            "document-unique",
            json.object([
              #("id", unique_json),
              #(
                "isStable",
                json.bool(fluid_ids.session_space_id_to_int(unique) < 0),
              ),
            ]),
          ),
          stage(
            "precision-limits",
            json.object([
              #("lastExactOffset", exact),
              #("firstRejectedOffset", rejected),
            ]),
          ),
          refusal,
          stage("creation-ranges", array(ranges)),
          stage(
            "serialization",
            json.object([
              #("withSession", with_session),
              #("summary", summary_bytes),
            ]),
          ),
          stage("cluster-growth-and-pending", growth),
          stage("uuid-carry", carry),
          stage("safe-integer-offsets", safe_integers),
        ]),
      ),
    ]),
  )
}

fn schedule_step(state: Schedule, step: String) -> Result(Schedule, String) {
  case step {
    "generate-two-each" -> {
      use #(a, initial_a) <- result.try(generate(state.a, 2))
      use #(b, initial_b) <- result.try(generate(state.b, 2))
      use a_ids <- result.try(descriptions(a, initial_a))
      use b_ids <- result.try(descriptions(b, initial_b))
      Ok(
        Schedule(
          ..state,
          a:,
          b:,
          initial_a:,
          initial_b:,
          before: json.object([#("a", a_ids), #("b", b_ids)]),
        ),
      )
    }
    "generate-eager-and-expansion" -> {
      use #(a, later_a) <- result.try(generate(state.a, 3))
      use #(b, later_b) <- result.try(generate(state.b, 3))
      Ok(Schedule(..state, a:, b:, later_a:, later_b:))
    }
    "finalize-a0" | "finalize-a1" -> {
      use #(a, range) <- result.try(take(state.a))
      finalize_both(Schedule(..state, a:), range)
    }
    "finalize-b0" | "finalize-b1" -> {
      use #(b, range) <- result.try(take(state.b))
      finalize_both(Schedule(..state, b:), range)
    }
    _ -> Error("Unknown ID schedule step: " <> step)
  }
}

fn finalize_both(
  state: Schedule,
  range: CreationRange,
) -> Result(Schedule, String) {
  use a <- result.try(native(fluid_ids.finalize(state.a, range)))
  use b <- result.try(native(fluid_ids.finalize(state.b, range)))
  Ok(Schedule(..state, a:, b:, ranges: list.append(state.ranges, [range])))
}

fn after_finalization(state: Schedule) -> Result(Json, String) {
  use initial_a <- result.try(descriptions(state.a, state.initial_a))
  use initial_b <- result.try(descriptions(state.b, state.initial_b))
  case state.later_a, state.later_b {
    [eager_a, ..expansion_a], [eager_b, ..expansion_b] -> {
      use eager_a <- result.try(describe(state.a, eager_a))
      use eager_b <- result.try(describe(state.b, eager_b))
      use expansion_a <- result.try(descriptions(state.a, expansion_a))
      use expansion_b <- result.try(descriptions(state.b, expansion_b))
      Ok(
        json.object([
          #("initialA", initial_a),
          #("initialB", initial_b),
          #("eagerA", eager_a),
          #("eagerB", eager_b),
          #("expansionA", expansion_a),
          #("expansionB", expansion_b),
        ]),
      )
    }
    _, _ -> Error("The ID schedule did not generate eager IDs")
  }
}

fn remote(
  origin: Compressor,
  target: Compressor,
  id: SessionSpaceId,
) -> Result(Json, String) {
  use op <- result.try(native(fluid_ids.to_op(origin, id)))
  use session <- result.try(
    native(fluid_ids.from_op(target, op, fluid_ids.local_session(origin))),
  )
  use stable <- result.try(native(fluid_ids.decompress(target, session)))
  use original <- result.try(native(fluid_ids.decompress(origin, id)))
  Ok(
    json.object([
      #("op", json.int(fluid_ids.op_id_to_int(op))),
      #("session", json.int(fluid_ids.session_space_id_to_int(session))),
      #("stable", json.string(fluid_ids.stable_id_to_string(stable))),
      #("matchesOrigin", json.bool(stable == original)),
    ]),
  )
}

fn precision(state: Compressor, raw: String) -> Result(Json, String) {
  use stable <- result.try(native(fluid_ids.stable_id(raw)))
  use id <- result.try(native(fluid_ids.recompress(state, stable)))
  let value = case id {
    Some(id) -> json.int(fluid_ids.session_space_id_to_int(id))
    option.None -> json.null()
  }
  Ok(json.object([#("status", json.string("accepted")), #("value", value)]))
}

fn malformed_allocation(input: Json) -> Result(Json, String) {
  use operation <- result.try(read(input, ["operation"], decode.string))
  use _ <- result.try(case operation {
    "finalizeCreationRange" -> Ok(Nil)
    _ -> Error("Unknown malformed allocation operation: " <> operation)
  })
  use session <- result.try(read(input, ["targetSession"], decode.string))
  use session <- result.try(native(fluid_ids.session_id(session)))
  use bytes <- result.try(read(input, ["initialSerializedState"], decode.string))
  use state <- result.try(
    native(fluid_ids.deserialize(json.string(bytes), session)),
  )
  use range <- result.try(field(input, ["range"]))
  let finalized =
    fluid_ids.creation_range_from_json(range)
    |> result.try(fn(range) { fluid_ids.finalize(state, range) })
  case finalized {
    Error(fluid_ids.InvalidRange("count")) -> {
      use post <- result.try(native(fluid_ids.serialize(state, True)))
      Ok(
        json.object([
          #("operation", json.string("malformed-allocation-refusal")),
          #("status", json.string("rejected")),
          #("error", json.string("Error: 0x755")),
          #(
            "statePreserved",
            json.bool(
              json.to_string(post) == json.to_string(json.string(bytes)),
            ),
          ),
          #("postState", post),
        ]),
      )
    }
    Error(error) ->
      Error("Unexpected allocation error: " <> string.inspect(error))
    Ok(_) -> Error("The native compressor accepted a malformed allocation")
  }
}

fn run_trace(input: Json) -> Result(Json, String) {
  use sessions <- result.try(read(
    input,
    ["sessions"],
    decode.list(decode.string),
  ))
  use size <- result.try(read(input, ["clusterSize"], decode.int))
  use clients <- result.try(list.try_map(sessions, create(_, size)))
  let clients =
    clients
    |> list.index_map(fn(client, index) { #(index, client) })
    |> dict.from_list
  use steps <- result.try(read(input, ["steps"], decode.list(json_ot.decoder())))
  use trace <- result.try(
    list.try_fold(steps, Trace(clients, [], []), fn(trace, step) {
      trace_step(trace, json_ot.to_json(step))
    }),
  )
  Ok(array(list.reverse(trace.observations)))
}

fn trace_step(trace: Trace, step: Json) -> Result(Trace, String) {
  use op <- result.try(read(step, ["op"], decode.string))
  use client <- result.try(read(step, ["client"], decode.int))
  use #(trace, value) <- result.try(case op {
    "restore" -> {
      use bytes <- result.try(read(step, ["serialized"], decode.string))
      use session <- result.try(read(step, ["session"], decode.string))
      use session <- result.try(native(fluid_ids.session_id(session)))
      use state <- result.try(
        native(fluid_ids.deserialize(json.string(bytes), session)),
      )
      Ok(#(
        Trace(..trace, clients: dict.insert(trace.clients, client, state)),
        json.string(
          fluid_ids.session_id_to_string(fluid_ids.local_session(state)),
        ),
      ))
    }
    _ -> {
      use state <- result.try(
        dict.get(trace.clients, client)
        |> result.map_error(fn(_) { "The ID trace references an absent client" }),
      )
      trace_operation(trace, state, step, op, client)
    }
  })
  let observation =
    json.object([
      #("op", json.string(op)),
      #("client", json.int(client)),
      #("value", value),
    ])
  Ok(Trace(..trace, observations: [observation, ..trace.observations]))
}

fn trace_operation(
  trace: Trace,
  state: Compressor,
  step: Json,
  op: String,
  client: Int,
) -> Result(#(Trace, Json), String) {
  case op {
    "generate" -> {
      use count <- result.try(read(step, ["count"], decode.int))
      use #(state, ids) <- result.try(generate(state, count))
      use value <- result.try(descriptions(state, ids))
      Ok(#(
        Trace(..trace, clients: dict.insert(trace.clients, client, state)),
        value,
      ))
    }
    "take" -> {
      let #(state, next) = fluid_ids.take_creation_range(state)
      let range = case next {
        Some(range) -> range
        option.None ->
          fluid_ids.CreationRange(fluid_ids.local_session(state), option.None)
      }
      use value <- result.try(native(fluid_ids.creation_range_to_json(range)))
      Ok(#(
        Trace(
          ..trace,
          clients: dict.insert(trace.clients, client, state),
          ranges: list.append(trace.ranges, [range]),
        ),
        value,
      ))
    }
    "finalize" -> {
      use index <- result.try(read(step, ["range"], decode.int))
      use range <- result.try(
        list.drop(trace.ranges, index)
        |> list.first
        |> result.map_error(fn(_) { "The ID trace references an absent range" }),
      )
      use state <- result.try(native(fluid_ids.finalize(state, range)))
      use value <- result.try(native(fluid_ids.serialize(state, False)))
      Ok(#(
        Trace(..trace, clients: dict.insert(trace.clients, client, state)),
        value,
      ))
    }
    "finalize-input" -> {
      use range <- result.try(field(step, ["range"]))
      use range <- result.try(native(fluid_ids.creation_range_from_json(range)))
      use state <- result.try(native(fluid_ids.finalize(state, range)))
      use value <- result.try(native(fluid_ids.serialize(state, False)))
      Ok(#(
        Trace(..trace, clients: dict.insert(trace.clients, client, state)),
        value,
      ))
    }
    "save" -> {
      use local <- result.try(read(step, ["local"], decode.bool))
      use value <- result.try(native(fluid_ids.serialize(state, local)))
      Ok(#(trace, value))
    }
    "describe" -> {
      use ids <- result.try(read(step, ["ids"], decode.list(decode.int)))
      use ids <- result.try(
        list.try_map(ids, fn(id) { native(fluid_ids.session_space_id(id)) }),
      )
      use value <- result.try(descriptions(state, ids))
      Ok(#(trace, value))
    }
    "normalize" -> {
      use origin <- result.try(read(step, ["origin"], decode.string))
      use origin <- result.try(native(fluid_ids.session_id(origin)))
      use id <- result.try(read(step, ["id"], decode.int))
      use id <- result.try(native(fluid_ids.op_id(id)))
      use id <- result.try(native(fluid_ids.from_op(state, id, origin)))
      use value <- result.try(describe(state, id))
      Ok(#(trace, value))
    }
    _ -> Error("Unknown ID trace operation: " <> op)
  }
}

fn describe(state: Compressor, id: SessionSpaceId) -> Result(Json, String) {
  use op <- result.try(native(fluid_ids.to_op(state, id)))
  use stable <- result.try(native(fluid_ids.decompress(state, id)))
  use recompressed <- result.try(native(fluid_ids.recompress(state, stable)))
  case recompressed {
    option.None -> Error("A generated ID could not be recompressed")
    Some(recompressed) ->
      Ok(
        json.object([
          #("session", json.int(fluid_ids.session_space_id_to_int(id))),
          #("op", json.int(fluid_ids.op_id_to_int(op))),
          #("final", json.bool(fluid_ids.session_space_id_to_int(id) >= 0)),
          #("stable", json.string(fluid_ids.stable_id_to_string(stable))),
          #(
            "recompressed",
            json.int(fluid_ids.session_space_id_to_int(recompressed)),
          ),
        ]),
      )
  }
}

fn descriptions(
  state: Compressor,
  ids: List(SessionSpaceId),
) -> Result(Json, String) {
  list.try_map(ids, describe(state, _)) |> result.map(array)
}

fn generate(
  state: Compressor,
  count: Int,
) -> Result(#(Compressor, List(SessionSpaceId)), String) {
  case count {
    0 -> Ok(#(state, []))
    n if n > 0 -> {
      use #(state, id) <- result.try(native(fluid_ids.generate(state)))
      use #(state, rest) <- result.try(generate(state, count - 1))
      Ok(#(state, [id, ..rest]))
    }
    _ -> Error("The ID generation count must not be negative")
  }
}

fn take(state: Compressor) -> Result(#(Compressor, CreationRange), String) {
  case fluid_ids.take_creation_range(state) {
    #(state, Some(range)) -> Ok(#(state, range))
    _ -> Error("The ID schedule took an empty range")
  }
}

fn create(raw: String, size: Int) -> Result(Compressor, String) {
  use session <- result.try(native(fluid_ids.session_id(raw)))
  native(fluid_ids.with_cluster_size(fluid_ids.new(session), size))
}

fn last(ids: List(a)) -> Result(a, String) {
  list.last(ids) |> result.map_error(fn(_) { "The ID schedule is incomplete" })
}

fn native(value: Result(a, IdError)) -> Result(a, String) {
  result.map_error(value, string.inspect)
}

fn read(
  input: Json,
  path: List(String),
  decoder: Decoder(a),
) -> Result(a, String) {
  json.parse(json.to_string(input), decode.at(path, decoder))
  |> result.map_error(fn(error) {
    "Invalid ID input at "
    <> string.join(path, ".")
    <> ": "
    <> string.inspect(error)
  })
}

fn field(input: Json, path: List(String)) -> Result(Json, String) {
  read(input, path, json_ot.decoder()) |> result.map(json_ot.to_json)
}

fn array(values: List(Json)) -> Json {
  json.array(values, fn(value) { value })
}

fn stage(name: String, value: Json) -> Json {
  json.object([#("stage", json.string(name)), #("value", value)])
}
