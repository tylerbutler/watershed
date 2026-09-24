//// Document-level Fluid ID compression.
////
//// This module follows the Fluid 3.1.0 compressor at commit
//// c3c5bf0ecd313362e83fe8a02b7d39e7e0736960. It has no Fluid runtime dependency.
//// Keep one compressor per document. Apply creation ranges in sequenced order.

import gleam/bit_array
import gleam/dynamic/decode.{type Decoder}
import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{type Order, Eq, Gt, Lt}
import gleam/result
import gleam/string

const max_safe_integer = 9_007_199_254_740_991

const limb_base = 4_294_967_296

// The UUID payload has 122 bits. Each limb fits in a JavaScript integer.
type Uuid {
  Uuid(high: Int, middle_high: Int, middle_low: Int, low: Int)
}

pub opaque type SessionId {
  SessionId(uuid: Uuid)
}

pub opaque type StableId {
  StableId(uuid: Uuid)
}

pub opaque type SessionSpaceId {
  SessionSpaceId(value: Int)
}

pub opaque type OpId {
  OpId(value: Int)
}

pub type IdError {
  InvalidUuid(value: String)
  UnsafeInteger(value: Int)
  InvalidRange(field: String)
  OutOfOrder(expected: Int, actual: Int)
  UnknownId(value: Int)
  UnknownSession(session: SessionId)
  UuidCollision(session: SessionId)
  IdSpaceExhausted
  InvalidSerialization(field: String)
  UnsupportedVersion(version: Int)
  SessionMismatch
}

pub type CreationRange {
  CreationRange(session_id: SessionId, ids: Option(RangeIds))
}

pub type RangeIds {
  RangeIds(
    first_gen_count: Int,
    count: Int,
    requested_cluster_size: Int,
    local_id_ranges: List(#(Int, Int)),
  )
}

type Cluster {
  Cluster(
    session: SessionId,
    first_gen: Int,
    base_final: Int,
    capacity: Int,
    count: Int,
  )
}

pub opaque type Compressor {
  Compressor(
    local: SessionId,
    sessions: List(SessionId),
    clusters: List(Cluster),
    generated: Int,
    taken: Int,
    locals: List(#(Int, Int)),
    requested_size: Int,
  )
}

/// Parse a version 4, RFC 4122 variant UUID. Hexadecimal letters are canonicalized.
pub fn session_id(raw: String) -> Result(SessionId, IdError) {
  parse_uuid(raw) |> result.map(SessionId)
}

pub fn stable_id(raw: String) -> Result(StableId, IdError) {
  parse_uuid(raw) |> result.map(StableId)
}

pub fn session_id_to_string(id: SessionId) -> String {
  uuid_string(id.uuid)
}

pub fn stable_id_to_string(id: StableId) -> String {
  uuid_string(id.uuid)
}

pub fn session_space_id(value: Int) -> Result(SessionSpaceId, IdError) {
  use _ <- result.try(safe_integer(value))
  Ok(SessionSpaceId(value))
}

pub fn op_id(value: Int) -> Result(OpId, IdError) {
  use _ <- result.try(safe_integer(value))
  Ok(OpId(value))
}

pub fn session_space_id_to_int(id: SessionSpaceId) -> Int {
  id.value
}

pub fn op_id_to_int(id: OpId) -> Int {
  id.value
}

pub fn new(session: SessionId) -> Compressor {
  Compressor(session, [session], [], 0, 0, [], 512)
}

pub fn local_session(state: Compressor) -> SessionId {
  state.local
}

/// A restored local session has generated IDs that must keep their identity.
pub fn has_local_state(state: Compressor) -> Bool {
  state.generated > 0 || state.taken > 0 || state.locals != []
}

/// Write the upstream format-2 base64 string as a JSON string.
/// Summaries exclude pending IDs and omit an empty local session.
pub fn serialize(
  state: Compressor,
  include_local: Bool,
) -> Result(Json, IdError) {
  let sessions =
    list.filter(state.sessions, fn(session) {
      include_local || finalized_gen(state, session) > 0
    })
  let indexed =
    list.index_map(sessions, fn(session, index) { #(session, index) })
  use clusters <- result.try(
    list.try_map(list.reverse(state.clusters), fn(cluster) {
      use #(_, index) <- result.try(
        list.find(indexed, fn(entry) { entry.0 == cluster.session })
        |> result.map_error(fn(_) { InvalidSerialization("sessionIndex") }),
      )
      Ok(write_numbers([index, cluster.capacity, cluster.count]))
    }),
  )
  let flag = case include_local {
    True -> 1
    False -> 0
  }
  let header =
    write_numbers([2, flag, list.length(sessions), list.length(clusters)])
  let session_bytes =
    sessions
    |> list.map(fn(session) { write_uuid(session.uuid) })
    |> bit_array.concat
  let local_bytes = case include_local {
    False -> <<>>
    True ->
      bit_array.concat([
        write_numbers([
          state.generated,
          state.taken + 1,
          list.length(state.locals),
        ]),
        ..list.map(list.reverse(state.locals), fn(range) {
          write_numbers([range.0, range.1])
        })
      ])
  }
  let bytes = bit_array.concat([header, session_bytes, ..clusters])
  Ok(
    json.string(bit_array.base64_encode(<<bytes:bits, local_bytes:bits>>, True)),
  )
}

/// Restore a summary with a new session, or resume local state with its saved session.
/// A different session cannot resume saved local state. A summary cannot resume a known session.
pub fn deserialize(
  data: Json,
  session: SessionId,
) -> Result(Compressor, IdError) {
  use encoded <- result.try(
    json.parse(json.to_string(data), decode.string)
    |> result.map_error(fn(_) { InvalidSerialization("base64 string") }),
  )
  use bytes <- result.try(
    bit_array.base64_decode(encoded)
    |> result.map_error(fn(_) { InvalidSerialization("base64") }),
  )
  use _ <- result.try(case bit_array.base64_encode(bytes, True) == encoded {
    True -> Ok(Nil)
    False -> Error(InvalidSerialization("base64"))
  })
  use #(version, bytes) <- result.try(read_number(bytes, "version"))
  use _ <- result.try(case version {
    2 -> Ok(Nil)
    _ -> Error(UnsupportedVersion(version))
  })
  use #(flag, bytes) <- result.try(read_number(bytes, "hasLocalState"))
  use _ <- result.try(case flag == 0 || flag == 1 {
    True -> Ok(Nil)
    False -> Error(InvalidSerialization("hasLocalState"))
  })
  use #(session_count, bytes) <- result.try(read_number(bytes, "sessionCount"))
  use #(cluster_count, bytes) <- result.try(read_number(bytes, "clusterCount"))
  use _ <- result.try(check_available(bytes, session_count, 16, "sessions"))
  use #(sessions, bytes) <- result.try(read_sessions(bytes, session_count, []))
  use all_sessions <- result.try(case flag, sessions {
    1, [first, ..] if first == session -> Ok(sessions)
    1, [] -> Error(InvalidSerialization("local session"))
    1, _ -> Error(SessionMismatch)
    0, _ ->
      case list.contains(sessions, session) {
        True -> Error(SessionMismatch)
        False -> Ok([session, ..sessions])
      }
    _, _ -> Error(InvalidSerialization("hasLocalState"))
  })
  let state = Compressor(..new(session), sessions: all_sessions)
  use _ <- result.try(check_available(bytes, cluster_count, 24, "clusters"))
  use #(state, bytes) <- result.try(read_clusters(
    bytes,
    cluster_count,
    sessions,
    state,
  ))
  use #(state, bytes) <- result.try(case flag {
    1 -> read_local_state(bytes, state)
    _ -> Ok(#(state, bytes))
  })
  case bytes {
    <<>> -> Ok(state)
    _ -> Error(InvalidSerialization("trailing bytes"))
  }
}

pub fn creation_range_to_json(range: CreationRange) -> Result(Json, IdError) {
  let session = #(
    "sessionId",
    json.string(session_id_to_string(range.session_id)),
  )
  case range.ids {
    None -> Ok(json.object([session]))
    Some(ids) -> {
      use _ <- result.try(validate_range(ids))
      Ok(
        json.object([
          session,
          #(
            "ids",
            json.object([
              #("firstGenCount", json.int(ids.first_gen_count)),
              #("count", json.int(ids.count)),
              #("requestedClusterSize", json.int(ids.requested_cluster_size)),
              #(
                "localIdRanges",
                json.array(ids.local_id_ranges, fn(range) {
                  json.array([range.0, range.1], json.int)
                }),
              ),
            ]),
          ),
        ]),
      )
    }
  }
}

/// Decode and validate a range before it enters document state.
pub fn creation_range_from_json(data: Json) -> Result(CreationRange, IdError) {
  use #(raw_session, ids) <- result.try(
    json.parse(json.to_string(data), creation_range_decoder())
    |> result.map_error(fn(_) { InvalidRange("JSON") }),
  )
  use session <- result.try(session_id(raw_session))
  use _ <- result.try(case ids {
    None -> Ok(Nil)
    Some(ids) -> validate_range(ids)
  })
  Ok(CreationRange(session, ids))
}

fn creation_range_decoder() -> Decoder(#(String, Option(RangeIds))) {
  use session <- decode.field("sessionId", decode.string)
  use ids <- decode.optional_field(
    "ids",
    None,
    decode.map(range_ids_decoder(), Some),
  )
  decode.success(#(session, ids))
}

fn range_ids_decoder() -> Decoder(RangeIds) {
  use first <- decode.field("firstGenCount", decode.int)
  use count <- decode.field("count", decode.int)
  use size <- decode.field("requestedClusterSize", decode.int)
  use locals <- decode.field("localIdRanges", decode.list(local_pair_decoder()))
  decode.success(RangeIds(first, count, size, locals))
}

fn local_pair_decoder() -> Decoder(#(Int, Int)) {
  use pair <- decode.then(decode.list(decode.int))
  case pair {
    [first, count] -> decode.success(#(first, count))
    _ -> decode.failure(#(0, 0), "a generation count and length pair")
  }
}

fn write_numbers(values: List(Int)) -> BitArray {
  values
  |> list.map(fn(value) { <<int.to_float(value):float-little>> })
  |> bit_array.concat
}

fn write_uuid(uuid: Uuid) -> BitArray {
  <<
    uuid.low:32-little,
    uuid.middle_low:32-little,
    uuid.middle_high:32-little,
    uuid.high:32-little,
  >>
}

fn read_number(
  bytes: BitArray,
  field: String,
) -> Result(#(Int, BitArray), IdError) {
  case bytes {
    <<value:float-little, rest:bytes>> ->
      case
        value >=. 0.0
        && value <=. 9_007_199_254_740_991.0
        && float.floor(value) == value
      {
        True -> Ok(#(float.truncate(value), rest))
        False -> Error(InvalidSerialization(field))
      }
    _ -> Error(InvalidSerialization(field))
  }
}

fn check_available(
  bytes: BitArray,
  count: Int,
  width: Int,
  field: String,
) -> Result(Nil, IdError) {
  case count <= bit_array.byte_size(bytes) / width {
    True -> Ok(Nil)
    False -> Error(InvalidSerialization(field))
  }
}

fn read_sessions(
  bytes: BitArray,
  count: Int,
  sessions: List(SessionId),
) -> Result(#(List(SessionId), BitArray), IdError) {
  case count, bytes {
    0, _ -> Ok(#(list.reverse(sessions), bytes))
    _,
      <<
        low:32-little,
        middle_low:32-little,
        middle_high:32-little,
        high:32-little,
        rest:bytes,
      >>
      if high < 67_108_864
    -> {
      let session = SessionId(Uuid(high, middle_high, middle_low, low))
      case list.contains(sessions, session) {
        True -> Error(InvalidSerialization("duplicate session"))
        False -> read_sessions(rest, count - 1, [session, ..sessions])
      }
    }
    _, _ -> Error(InvalidSerialization("session UUID"))
  }
}

fn read_clusters(
  bytes: BitArray,
  count: Int,
  sessions: List(SessionId),
  state: Compressor,
) -> Result(#(Compressor, BitArray), IdError) {
  case count {
    0 -> Ok(#(state, bytes))
    _ -> {
      use #(index, bytes) <- result.try(read_number(bytes, "sessionIndex"))
      use #(capacity, bytes) <- result.try(read_number(bytes, "capacity"))
      use #(count_in_cluster, bytes) <- result.try(read_number(bytes, "count"))
      use owner <- result.try(
        list.drop(sessions, index)
        |> list.first
        |> result.map_error(fn(_) { InvalidSerialization("sessionIndex") }),
      )
      use _ <- result.try(
        case
          capacity > 0 && count_in_cluster > 0 && count_in_cluster <= capacity
        {
          True -> Ok(Nil)
          False -> Error(InvalidSerialization("cluster count or capacity"))
        },
      )
      use first <- result.try(
        case
          list.find(state.clusters, fn(cluster) { cluster.session == owner })
        {
          Error(Nil) -> Ok(1)
          Ok(last) if last.count == last.capacity ->
            checked_add(last.first_gen, last.capacity)
          Ok(_) -> Error(InvalidSerialization("unfilled preceding cluster"))
        },
      )
      use clusters <- result.try(add_cluster(
        state,
        owner,
        first,
        capacity,
        count_in_cluster,
      ))
      read_clusters(bytes, count - 1, sessions, Compressor(..state, clusters:))
    }
  }
}

fn read_local_state(
  bytes: BitArray,
  state: Compressor,
) -> Result(#(Compressor, BitArray), IdError) {
  use #(generated, bytes) <- result.try(read_number(bytes, "generated"))
  use #(next, bytes) <- result.try(read_number(bytes, "nextRangeBaseGenCount"))
  use #(count, bytes) <- result.try(read_number(bytes, "normalizerCount"))
  use _ <- result.try(
    case
      generated < max_safe_integer
      && next >= 1
      && next - 1 <= generated
      && finalized_gen(state, state.local) <= generated
    {
      True -> Ok(Nil)
      False -> Error(InvalidSerialization("local generation counts"))
    },
  )
  use _ <- result.try(case generated {
    0 -> Ok(Nil)
    _ ->
      uuid_offset(state.local.uuid, generated - 1) |> result.map(fn(_) { Nil })
  })
  use _ <- result.try(check_available(bytes, count, 16, "local ranges"))
  use #(locals, bytes) <- result.try(read_locals(bytes, count, [], 1, generated))
  let state = Compressor(..state, generated:, taken: next - 1, locals:)
  use _ <- result.try(validate_local_coverage(state))
  Ok(#(state, bytes))
}

fn read_locals(
  bytes: BitArray,
  count: Int,
  locals: List(#(Int, Int)),
  next: Int,
  generated: Int,
) -> Result(#(List(#(Int, Int)), BitArray), IdError) {
  case count {
    0 -> Ok(#(locals, bytes))
    _ -> {
      use #(first, bytes) <- result.try(read_number(
        bytes,
        "local firstGenCount",
      ))
      use #(length, bytes) <- result.try(read_number(bytes, "local count"))
      use _ <- result.try(validate_local_ranges(
        [#(first, length)],
        next,
        generated,
      ))
      read_locals(
        bytes,
        count - 1,
        add_local(locals, first, length),
        first + length,
        generated,
      )
    }
  }
}

fn validate_local_coverage(state: Compressor) -> Result(Nil, IdError) {
  let allocations =
    state.clusters
    |> list.filter(fn(cluster) { cluster.session == state.local })
    |> list.map(fn(cluster) { #(cluster.first_gen, cluster.capacity) })
  let intervals =
    list.append(allocations, state.locals)
    |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
  use covered <- result.try(
    list.try_fold(intervals, 0, fn(covered, range) {
      case range.0 <= covered + 1 {
        False -> Error(InvalidSerialization("missing local allocations"))
        True ->
          Ok(int.min(
            state.generated,
            int.max(covered, range.0 + { range.1 - 1 }),
          ))
      }
    }),
  )
  case covered >= state.generated {
    True -> Ok(Nil)
    False -> Error(InvalidSerialization("missing local allocations"))
  }
}

/// Select the reservation size for subsequent creation ranges.
/// Restoration resets this transient setting to the upstream default of 512.
pub fn with_cluster_size(
  state: Compressor,
  size: Int,
) -> Result(Compressor, IdError) {
  use _ <- result.try(validate_cluster_size(size))
  Ok(Compressor(..state, requested_size: size))
}

pub fn generate(
  state: Compressor,
) -> Result(#(Compressor, SessionSpaceId), IdError) {
  // Leave room for the next range cursor in the serialized safe-integer domain.
  case state.generated >= max_safe_integer - 1 {
    True -> Error(IdSpaceExhausted)
    False -> {
      use _ <- result.try(uuid_offset(state.local.uuid, state.generated))
      let gen = state.generated + 1
      let state = Compressor(..state, generated: gen)
      case cluster_by_gen(state, state.local, gen, True) {
        Some(cluster) ->
          Ok(#(
            state,
            SessionSpaceId(cluster.base_final + { gen - cluster.first_gen }),
          ))
        None ->
          Ok(#(
            Compressor(..state, locals: add_local(state.locals, gen, 1)),
            SessionSpaceId(-gen),
          ))
      }
    }
  }
}

pub fn take_creation_range(
  state: Compressor,
) -> #(Compressor, Option(CreationRange)) {
  case state.generated == state.taken {
    True -> #(state, None)
    False -> {
      let ids =
        RangeIds(
          state.taken + 1,
          state.generated - state.taken,
          state.requested_size,
          local_ranges_between(state.locals, state.taken + 1, state.generated),
        )
      #(
        Compressor(..state, taken: state.generated),
        Some(CreationRange(state.local, Some(ids))),
      )
    }
  }
}

/// Retake all unacknowledged IDs after reconnect.
pub fn take_unfinalized_range(
  state: Compressor,
) -> #(Compressor, Option(CreationRange)) {
  let finalized = finalized_gen(state, state.local)
  take_creation_range(Compressor(..state, taken: finalized))
}

/// Return a candidate state only after the complete range has been validated.
pub fn finalize(
  state: Compressor,
  range: CreationRange,
) -> Result(Compressor, IdError) {
  case range.ids {
    None -> Ok(state)
    Some(ids) -> {
      use _ <- result.try(validate_range(ids))
      use expected <- result.try(checked_add(
        finalized_gen(state, range.session_id),
        1,
      ))
      case ids.first_gen_count == expected {
        False -> Error(OutOfOrder(expected, ids.first_gen_count))
        True -> {
          use _ <- result.try(validate_local_finalization(
            state,
            range.session_id,
            ids,
          ))
          use clusters <- result.try(finalize_clusters(
            state,
            range.session_id,
            ids,
          ))
          let sessions = case list.contains(state.sessions, range.session_id) {
            True -> state.sessions
            False -> list.append(state.sessions, [range.session_id])
          }
          Ok(Compressor(..state, sessions:, clusters:))
        }
      }
    }
  }
}

pub fn to_op(state: Compressor, id: SessionSpaceId) -> Result(OpId, IdError) {
  case id.value >= 0 {
    True -> {
      use _ <- result.try(decompress(state, id))
      Ok(OpId(id.value))
    }
    False ->
      case is_local(state, -id.value) {
        False -> Error(UnknownId(id.value))
        True ->
          case cluster_by_gen(state, state.local, -id.value, True) {
            None -> Ok(OpId(id.value))
            Some(cluster) ->
              Ok(OpId(cluster.base_final + { -id.value - cluster.first_gen }))
          }
      }
  }
}

pub fn from_op(
  state: Compressor,
  id: OpId,
  origin: SessionId,
) -> Result(SessionSpaceId, IdError) {
  case id.value >= 0 {
    True ->
      case cluster_by_final(state, id.value) {
        Some(cluster) if cluster.session == state.local -> {
          let gen = cluster.first_gen + { id.value - cluster.base_final }
          case is_local(state, gen), gen <= state.generated {
            True, _ -> Ok(SessionSpaceId(-gen))
            False, True -> Ok(SessionSpaceId(id.value))
            False, False -> Error(UnknownId(id.value))
          }
        }
        _ -> {
          let limit = case state.clusters {
            [] -> 0
            [last, ..] -> last.base_final + last.count
          }
          case id.value < limit {
            True -> Ok(SessionSpaceId(id.value))
            False -> Error(UnknownId(id.value))
          }
        }
      }
    False if origin == state.local ->
      case is_local(state, -id.value) {
        True -> Ok(SessionSpaceId(id.value))
        False -> Error(UnknownId(id.value))
      }
    False ->
      case list.contains(state.sessions, origin) {
        False -> Error(UnknownSession(origin))
        True ->
          case cluster_by_gen(state, origin, -id.value, False) {
            None -> Error(UnknownId(id.value))
            Some(cluster) ->
              Ok(SessionSpaceId(
                cluster.base_final + { -id.value - cluster.first_gen },
              ))
          }
      }
  }
}

pub fn decompress(
  state: Compressor,
  id: SessionSpaceId,
) -> Result(StableId, IdError) {
  case id.value < 0 {
    True ->
      case is_local(state, -id.value) {
        True ->
          uuid_offset(state.local.uuid, -id.value - 1) |> result.map(StableId)
        False -> Error(UnknownId(id.value))
      }
    False ->
      case cluster_by_final(state, id.value) {
        None -> Error(UnknownId(id.value))
        Some(cluster) -> {
          let offset = id.value - cluster.base_final
          let gen = cluster.first_gen + offset
          case
            offset < cluster.count
            || cluster.session == state.local
            && gen <= state.generated
            && !is_local(state, gen)
          {
            True ->
              uuid_offset(cluster.session.uuid, gen - 1) |> result.map(StableId)
            False -> Error(UnknownId(id.value))
          }
        }
      }
  }
}

/// Return None for a stable ID outside the known allocation space.
pub fn recompress(
  state: Compressor,
  stable: StableId,
) -> Result(Option(SessionSpaceId), IdError) {
  let matched =
    list.find_map(state.clusters, fn(cluster) {
      case uuid_difference(stable.uuid, cluster.session.uuid) {
        Some(offset)
          if offset >= cluster.first_gen - 1
          && offset - { cluster.first_gen - 1 } < cluster.capacity
        -> Ok(#(cluster, offset + 1))
        _ -> Error(Nil)
      }
    })
  case matched {
    Ok(#(cluster, gen)) if cluster.session == state.local ->
      case is_local(state, gen), gen <= state.generated {
        True, _ -> Ok(Some(SessionSpaceId(-gen)))
        False, True ->
          Ok(
            Some(SessionSpaceId(
              cluster.base_final + { gen - cluster.first_gen },
            )),
          )
        False, False -> Error(UnknownId(-gen))
      }
    Ok(#(cluster, gen)) ->
      Ok(Some(SessionSpaceId(cluster.base_final + { gen - cluster.first_gen })))
    Error(Nil) ->
      case uuid_difference(stable.uuid, state.local.uuid) {
        Some(offset) if offset < max_safe_integer ->
          case is_local(state, offset + 1) {
            True -> Ok(Some(SessionSpaceId(-offset - 1)))
            False -> Ok(None)
          }
        _ -> Ok(None)
      }
  }
}

fn safe_integer(value: Int) -> Result(Nil, IdError) {
  case value >= -max_safe_integer && value <= max_safe_integer {
    True -> Ok(Nil)
    False -> Error(UnsafeInteger(value))
  }
}

fn checked_add(a: Int, b: Int) -> Result(Int, IdError) {
  case a >= 0 && b >= 0 && b <= max_safe_integer - a {
    True -> Ok(a + b)
    False -> Error(IdSpaceExhausted)
  }
}

fn validate_cluster_size(size: Int) -> Result(Nil, IdError) {
  case size >= 1 && size <= 1_048_576 {
    True -> Ok(Nil)
    False -> Error(InvalidRange("requestedClusterSize"))
  }
}

fn validate_range(ids: RangeIds) -> Result(Nil, IdError) {
  use _ <- result.try(safe_integer(ids.first_gen_count))
  use _ <- result.try(safe_integer(ids.count))
  use _ <- result.try(validate_cluster_size(ids.requested_cluster_size))
  case ids.first_gen_count >= 1, ids.count >= 1 {
    False, _ -> Error(InvalidRange("firstGenCount"))
    _, False -> Error(InvalidRange("count"))
    True, True -> {
      use last <- result.try(checked_add(ids.first_gen_count, ids.count - 1))
      validate_local_ranges(ids.local_id_ranges, ids.first_gen_count, last)
    }
  }
}

fn validate_local_ranges(
  ranges: List(#(Int, Int)),
  first: Int,
  last: Int,
) -> Result(Nil, IdError) {
  case ranges {
    [] -> Ok(Nil)
    [#(start, count), ..rest] -> {
      use _ <- result.try(safe_integer(start))
      use _ <- result.try(safe_integer(count))
      case
        start >= first
        && start <= last
        && count > 0
        && count - 1 <= last - start
      {
        True ->
          case rest {
            [] -> Ok(Nil)
            _ -> {
              use next <- result.try(checked_add(start, count))
              validate_local_ranges(rest, next, last)
            }
          }
        False -> Error(InvalidRange("localIdRanges"))
      }
    }
  }
}

fn validate_local_finalization(
  state: Compressor,
  owner: SessionId,
  ids: RangeIds,
) -> Result(Nil, IdError) {
  let last = ids.first_gen_count + { ids.count - 1 }
  case owner == state.local {
    False -> Ok(Nil)
    True ->
      case
        last <= state.generated
        && ids.local_id_ranges
        == local_ranges_between(state.locals, ids.first_gen_count, last)
      {
        True -> Ok(Nil)
        False -> Error(InvalidRange("local allocation"))
      }
  }
}

fn finalize_clusters(
  state: Compressor,
  owner: SessionId,
  ids: RangeIds,
) -> Result(List(Cluster), IdError) {
  case list.find(state.clusters, fn(cluster) { cluster.session == owner }) {
    Error(Nil) -> {
      use capacity <- result.try(checked_add(
        ids.count,
        ids.requested_cluster_size,
      ))
      add_cluster(state, owner, 1, capacity, ids.count)
    }
    Ok(last) -> {
      let remaining = last.capacity - last.count
      case ids.count <= remaining {
        True ->
          Ok(replace_cluster(
            state.clusters,
            Cluster(..last, count: last.count + ids.count),
          ))
        False -> {
          let overflow = ids.count - remaining
          use claimed <- result.try(checked_add(
            overflow,
            ids.requested_cluster_size,
          ))
          case state.clusters {
            [global, ..] if global.base_final == last.base_final -> {
              use capacity <- result.try(checked_add(last.capacity, claimed))
              let expanded =
                Cluster(..last, capacity:, count: last.count + ids.count)
              use _ <- result.try(validate_cluster(state.clusters, expanded))
              Ok(replace_cluster(state.clusters, expanded))
            }
            _ -> {
              let clusters =
                replace_cluster(
                  state.clusters,
                  Cluster(..last, count: last.capacity),
                )
              use first <- result.try(checked_add(last.first_gen, last.capacity))
              add_cluster(
                Compressor(..state, clusters:),
                owner,
                first,
                claimed,
                overflow,
              )
            }
          }
        }
      }
    }
  }
}

fn add_cluster(
  state: Compressor,
  owner: SessionId,
  first: Int,
  capacity: Int,
  count: Int,
) -> Result(List(Cluster), IdError) {
  let base = case state.clusters {
    [] -> 0
    [last, ..] -> last.base_final + last.capacity
  }
  let cluster = Cluster(owner, first, base, capacity, count)
  use _ <- result.try(validate_cluster(state.clusters, cluster))
  Ok([cluster, ..state.clusters])
}

fn validate_cluster(
  clusters: List(Cluster),
  cluster: Cluster,
) -> Result(Nil, IdError) {
  use _ <- result.try(checked_add(cluster.base_final, cluster.capacity))
  use last_gen <- result.try(checked_add(
    cluster.first_gen,
    cluster.capacity - 1,
  ))
  use first <- result.try(uuid_offset(
    cluster.session.uuid,
    cluster.first_gen - 1,
  ))
  use last <- result.try(uuid_offset(cluster.session.uuid, last_gen - 1))
  list.try_fold(clusters, Nil, fn(_, other) {
    case other.session == cluster.session {
      True -> Ok(Nil)
      False -> {
        use other_first <- result.try(uuid_offset(
          other.session.uuid,
          other.first_gen - 1,
        ))
        use other_last <- result.try(uuid_offset(
          other.session.uuid,
          other.first_gen + { other.capacity - 2 },
        ))
        case
          uuid_compare(first, other_last) != Gt
          && uuid_compare(last, other_first) != Lt
        {
          True -> Error(UuidCollision(other.session))
          False -> Ok(Nil)
        }
      }
    }
  })
}

fn replace_cluster(clusters: List(Cluster), updated: Cluster) -> List(Cluster) {
  list.map(clusters, fn(cluster) {
    case cluster.base_final == updated.base_final {
      True -> updated
      False -> cluster
    }
  })
}

// ponytail: Cluster lookup is linear. Add an index only after profiling.
fn cluster_by_gen(
  state: Compressor,
  owner: SessionId,
  gen: Int,
  allocated: Bool,
) -> Option(Cluster) {
  list.find(state.clusters, fn(cluster) {
    let count = case allocated {
      True -> cluster.capacity
      False -> cluster.count
    }
    cluster.session == owner
    && gen >= cluster.first_gen
    && gen - cluster.first_gen < count
  })
  |> option.from_result
}

fn cluster_by_final(state: Compressor, id: Int) -> Option(Cluster) {
  list.find(state.clusters, fn(cluster) {
    id >= cluster.base_final && id - cluster.base_final < cluster.capacity
  })
  |> option.from_result
}

fn finalized_gen(state: Compressor, owner: SessionId) -> Int {
  case list.find(state.clusters, fn(cluster) { cluster.session == owner }) {
    Ok(cluster) -> cluster.first_gen + { cluster.count - 1 }
    Error(Nil) -> 0
  }
}

fn is_local(state: Compressor, gen: Int) -> Bool {
  list.any(state.locals, fn(range) { gen >= range.0 && gen - range.0 < range.1 })
}

fn add_local(
  ranges: List(#(Int, Int)),
  first: Int,
  count: Int,
) -> List(#(Int, Int)) {
  case ranges {
    [#(start, length), ..rest] if first - start == length -> [
      #(start, length + count),
      ..rest
    ]
    _ -> [#(first, count), ..ranges]
  }
}

fn local_ranges_between(
  ranges: List(#(Int, Int)),
  first: Int,
  last: Int,
) -> List(#(Int, Int)) {
  ranges
  |> list.reverse
  |> list.filter_map(fn(range) {
    let start = int.max(first, range.0)
    let end = int.min(last, range.0 + { range.1 - 1 })
    case end >= start {
      True -> Ok(#(start, end - start + 1))
      False -> Error(Nil)
    }
  })
}

fn parse_uuid(raw: String) -> Result(Uuid, IdError) {
  case string.split(raw, "-") {
    [a, b, c, d, e] -> {
      use _ <- result.try(case list.map([a, b, c, d, e], string.byte_size) {
        [8, 4, 4, 4, 12] -> Ok(Nil)
        _ -> Error(InvalidUuid(raw))
      })
      use values <- result.try(
        list.try_map([a, b, c, d, e], fn(part) {
          case
            list.all(string.to_graphemes(part), fn(char) {
              string.contains("0123456789abcdefABCDEF", char)
            })
          {
            False -> Error(InvalidUuid(raw))
            True ->
              int.base_parse(part, 16)
              |> result.map_error(fn(_) { InvalidUuid(raw) })
          }
        }),
      )
      case values {
        [a, b, c, d, e]
          if c >= 16_384 && c <= 20_479 && d >= 32_768 && d <= 49_151
        -> {
          let middle = c - 16_384
          Ok(Uuid(
            a / 64,
            a % 64 * 67_108_864 + b * 1024 + middle / 4,
            middle % 4 * 1_073_741_824 + { d - 32_768 } * 65_536 + e / limb_base,
            e % limb_base,
          ))
        }
        _ -> Error(InvalidUuid(raw))
      }
    }
    _ -> Error(InvalidUuid(raw))
  }
}

fn uuid_string(uuid: Uuid) -> String {
  let a = uuid.high * 64 + uuid.middle_high / 67_108_864
  let b = uuid.middle_high / 1024 % 65_536
  let c = 16_384 + uuid.middle_high % 1024 * 4 + uuid.middle_low / 1_073_741_824
  let d = 32_768 + uuid.middle_low / 65_536 % 16_384
  let e = uuid.middle_low % 65_536 * limb_base + uuid.low
  hex(a, 8)
  <> "-"
  <> hex(b, 4)
  <> "-"
  <> hex(c, 4)
  <> "-"
  <> hex(d, 4)
  <> "-"
  <> hex(e, 12)
}

fn hex(value: Int, width: Int) -> String {
  value |> int.to_base16 |> string.lowercase |> string.pad_start(width, "0")
}

fn uuid_offset(uuid: Uuid, offset: Int) -> Result(Uuid, IdError) {
  let low = uuid.low + offset % limb_base
  let middle_low = uuid.middle_low + offset / limb_base + low / limb_base
  let middle_high = uuid.middle_high + middle_low / limb_base
  let high = uuid.high + middle_high / limb_base
  case high < 67_108_864 {
    True ->
      Ok(Uuid(
        high,
        middle_high % limb_base,
        middle_low % limb_base,
        low % limb_base,
      ))
    False -> Error(IdSpaceExhausted)
  }
}

fn uuid_compare(a: Uuid, b: Uuid) -> Order {
  case int.compare(a.high, b.high) {
    Eq ->
      case int.compare(a.middle_high, b.middle_high) {
        Eq ->
          case int.compare(a.middle_low, b.middle_low) {
            Eq -> int.compare(a.low, b.low)
            order -> order
          }
        order -> order
      }
    order -> order
  }
}

fn subtract_limb(a: Int, b: Int, borrow: Int) -> #(Int, Int) {
  let difference = a - b - borrow
  case difference < 0 {
    True -> #(difference + limb_base, 1)
    False -> #(difference, 0)
  }
}

fn uuid_difference(a: Uuid, b: Uuid) -> Option(Int) {
  let #(low, borrow) = subtract_limb(a.low, b.low, 0)
  let #(middle_low, borrow) = subtract_limb(a.middle_low, b.middle_low, borrow)
  let #(middle_high, borrow) =
    subtract_limb(a.middle_high, b.middle_high, borrow)
  case
    a.high - b.high - borrow == 0 && middle_high == 0 && middle_low <= 2_097_151
  {
    True -> Some(middle_low * limb_base + low)
    False -> None
  }
}
