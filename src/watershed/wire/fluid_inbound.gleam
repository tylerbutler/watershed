//// Bounded normalization for inbound Fluid runtime operations.

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import spillway/types.{type SequencedDocumentMessage, SequencedDocumentMessage}
import watershed/wire
import watershed/wire/fluid_container
import watershed/wire/lz4

pub opaque type State {
  State(limits: Limits, streams: Dict(String, Partial), buffered_bytes: Int)
}

type Partial {
  Partial(
    reversed_pieces: List(String),
    received: Int,
    total: Option(Int),
    bytes: Int,
  )
}

pub type Limits {
  Limits(
    max_packed_bytes: Int,
    max_decoded_bytes: Int,
    max_buffered_bytes: Int,
    max_streams: Int,
    max_chunks: Int,
  )
}

pub type Payload {
  NonOperation
  Incomplete
  Complete(
    representative: SequencedDocumentMessage,
    batch: fluid_container.DecodedBatch,
  )
}

pub type Step {
  Step(state: State, payload: Payload)
}

pub type Error {
  UnsupportedCompression(String)
  InvalidPackedPayload(String)
  InvalidChunk(String)
  LimitExceeded(String)
  ContainerFailure(fluid_container.ContainerError)
}

type Chunk {
  Chunk(
    id: Int,
    total: Int,
    contents: String,
    original_type: Option(String),
    original_compression: Option(String),
    original_metadata: Option(Dynamic),
  )
}

pub fn default_limits() -> Limits {
  Limits(
    max_packed_bytes: 16 * 1024 * 1024,
    max_decoded_bytes: 16 * 1024 * 1024,
    max_buffered_bytes: 16 * 1024 * 1024,
    max_streams: 64,
    max_chunks: 128,
  )
}

pub fn new(limits: Limits) -> State {
  State(limits:, streams: dict.new(), buffered_bytes: 0)
}

pub fn step(
  state: State,
  envelope: wire.SequencedEnvelope,
) -> Result(Step, Error) {
  case envelope.message.message_type {
    "op" -> step_operation(state, envelope)
    _ -> Ok(Step(state, NonOperation))
  }
}

pub fn remove_client(state: State, client_id: String) -> State {
  case dict.get(state.streams, client_id) {
    Error(_) -> state
    Ok(partial) ->
      State(
        ..state,
        streams: dict.delete(state.streams, client_id),
        buffered_bytes: state.buffered_bytes - partial.bytes,
      )
  }
}

pub fn partial_chunks(state: State) -> List(#(String, List(String))) {
  state.streams
  |> dict.to_list
  |> list.map(fn(entry) { #(entry.0, list.reverse(entry.1.reversed_pieces)) })
}

pub fn restore(
  limits: Limits,
  partials: List(#(String, List(String))),
) -> Result(State, Error) {
  list.fold(partials, Ok(new(limits)), fn(outcome, entry) {
    use state <- result.try(outcome)
    let #(client_id, pieces) = entry
    use _ <- result.try(case client_id == "" {
      True -> Error(InvalidChunk("partial stream has an empty sender"))
      False -> Ok(Nil)
    })
    use _ <- result.try(case pieces {
      [] -> Error(InvalidChunk("partial stream has no pieces"))
      _ -> Ok(Nil)
    })
    use _ <- result.try(case dict.has_key(state.streams, client_id) {
      True -> Error(InvalidChunk("partial stream has a duplicate sender"))
      False -> Ok(Nil)
    })
    let count = list.length(pieces)
    use _ <- result.try(check_chunk_count(limits, count))
    let bytes =
      pieces
      |> list.fold(0, fn(total, piece) { total + string.byte_size(piece) })
    use _ <- result.try(check_packed_limit(limits, bytes))
    use _ <- result.try(check_buffered_limit(
      limits,
      state.buffered_bytes + bytes,
    ))
    use _ <- result.try(check_stream_limit(limits, dict.size(state.streams) + 1))
    Ok(
      State(
        ..state,
        streams: dict.insert(
          state.streams,
          client_id,
          Partial(list.reverse(pieces), count, None, bytes),
        ),
        buffered_bytes: state.buffered_bytes + bytes,
      ),
    )
  })
}

fn step_operation(
  state: State,
  envelope: wire.SequencedEnvelope,
) -> Result(Step, Error) {
  case decode.run(envelope.message.contents, message_type_decoder()) {
    Ok("chunkedOp") -> step_chunk(state, envelope)
    Ok(_) | Error(_) ->
      step_complete(state, envelope, envelope.message.contents)
  }
}

fn step_chunk(
  state: State,
  envelope: wire.SequencedEnvelope,
) -> Result(Step, Error) {
  use _ <- result.try(case envelope.compression {
    None -> Ok(Nil)
    Some(_) -> Error(InvalidChunk("chunk message has outer compression"))
  })
  use sender <- result.try(case envelope.message.client_id {
    Some(sender) if sender != "" -> Ok(sender)
    _ -> Error(InvalidChunk("chunk stream has no sender"))
  })
  use chunk <- result.try(
    decode.run(envelope.message.contents, chunk_decoder())
    |> result.map_error(fn(_) { InvalidChunk("invalid chunk message") }),
  )
  use _ <- result.try(check_chunk_count(state.limits, chunk.total))
  use _ <- result.try(case chunk.id > 0 && chunk.id <= chunk.total {
    True -> Ok(Nil)
    False -> Error(InvalidChunk("chunk identity is outside its stream"))
  })
  let existing = dict.get(state.streams, sender)
  let partial = case existing {
    Ok(partial) -> partial
    Error(_) -> Partial([], 0, Some(chunk.total), 0)
  }
  use _ <- result.try(case chunk.id == partial.received + 1 {
    True -> Ok(Nil)
    False -> Error(InvalidChunk("chunk identity is not the next value"))
  })
  use _ <- result.try(case partial.total {
    Some(total) if total != chunk.total ->
      Error(InvalidChunk("chunk total changed"))
    _ -> Ok(Nil)
  })
  use _ <- result.try(case existing, chunk.id {
    Error(_), 1 -> Ok(Nil)
    Error(_), _ ->
      Error(InvalidChunk("chunk stream is missing its first piece"))
    _, _ -> Ok(Nil)
  })
  use _ <- result.try(case existing, dict.size(state.streams) {
    Error(_), count -> check_stream_limit(state.limits, count + 1)
    _, _ -> Ok(Nil)
  })
  let piece_bytes = string.byte_size(chunk.contents)
  let packed_bytes = partial.bytes + piece_bytes
  use _ <- result.try(check_packed_limit(state.limits, packed_bytes))
  use _ <- result.try(check_buffered_limit(
    state.limits,
    state.buffered_bytes + piece_bytes,
  ))
  case chunk.id == chunk.total {
    False -> {
      use _ <- result.try(
        case
          chunk.original_type,
          chunk.original_compression,
          chunk.original_metadata
        {
          None, None, None -> Ok(Nil)
          _, _, _ -> Error(InvalidChunk("non-final chunk has original fields"))
        },
      )
      let next =
        Partial(
          [chunk.contents, ..partial.reversed_pieces],
          chunk.id,
          Some(chunk.total),
          packed_bytes,
        )
      Ok(Step(
        State(
          ..state,
          streams: dict.insert(state.streams, sender, next),
          buffered_bytes: state.buffered_bytes + piece_bytes,
        ),
        Incomplete,
      ))
    }
    True -> {
      use original_type <- result.try(case chunk.original_type {
        Some(value) -> Ok(value)
        None -> Error(InvalidChunk("final chunk has no original type"))
      })
      use _ <- result.try(case original_type {
        "component" -> Ok(Nil)
        value -> Error(InvalidChunk("unsupported original type: " <> value))
      })
      use compression <- result.try(case chunk.original_compression {
        Some(value) -> Ok(value)
        None -> Error(InvalidChunk("final chunk has no original compression"))
      })
      let packed =
        [chunk.contents, ..partial.reversed_pieces]
        |> list.reverse
        |> string.concat
      let metadata = chunk.original_metadata
      let representative =
        SequencedDocumentMessage(
          ..envelope.message,
          message_type: "op",
          metadata: metadata,
        )
      let completed_state =
        State(
          ..state,
          streams: dict.delete(state.streams, sender),
          buffered_bytes: state.buffered_bytes - partial.bytes,
        )
      use packed_contents <- result.try(
        json.parse(packed, decode.dynamic)
        |> result.map_error(fn(_) {
          InvalidPackedPayload("reassembled payload is not JSON")
        }),
      )
      step_complete(
        completed_state,
        wire.SequencedEnvelope(representative, Some(compression)),
        packed_contents,
      )
    }
  }
}

fn step_complete(
  state: State,
  envelope: wire.SequencedEnvelope,
  contents: Dynamic,
) -> Result(Step, Error) {
  use json_contents <- result.try(
    decode.run(contents, wire.json_value_decoder())
    |> result.map_error(fn(_) {
      InvalidPackedPayload("operation contents are not JSON")
    }),
  )
  case envelope.compression {
    None -> {
      use _ <- result.try(case has_packed_contents(contents) {
        True ->
          Error(InvalidPackedPayload(
            "packed contents require a compression marker",
          ))
        False -> Ok(Nil)
      })
      finish(state, envelope.message, contents, json_contents)
    }
    Some("lz4") -> {
      let packed_text = json.to_string(json_contents)
      use _ <- result.try(check_packed_limit(
        state.limits,
        string.byte_size(packed_text),
      ))
      use packed <- result.try(
        decode.run(contents, packed_decoder())
        |> result.map_error(fn(_) {
          InvalidPackedPayload("compressed operation has no packed contents")
        }),
      )
      use frame <- result.try(
        bit_array.base64_decode(packed)
        |> result.map_error(fn(_) {
          InvalidPackedPayload("packed contents are not valid base64")
        }),
      )
      use decoded <- result.try(
        lz4.decompress(frame, state.limits.max_decoded_bytes)
        |> result.map_error(map_lz4_error),
      )
      use text <- result.try(
        bit_array.to_string(decoded)
        |> result.map_error(fn(_) {
          InvalidPackedPayload("decoded contents are not valid UTF-8")
        }),
      )
      use logical <- result.try(
        json.parse(text, decode.list(decode.dynamic))
        |> result.map_error(fn(_) {
          InvalidPackedPayload("decoded contents are not a JSON array")
        }),
      )
      use logical <- result.try(case logical {
        [logical] -> Ok(logical)
        _ ->
          Error(InvalidPackedPayload(
            "compressed payload must contain one runtime message",
          ))
      })
      use _ <- result.try(case has_nested_compression(logical) {
        Ok(True) ->
          Error(InvalidPackedPayload("nested compression is not supported"))
        Ok(False) -> Ok(Nil)
        Error(_) ->
          Error(InvalidPackedPayload("invalid nested compression marker"))
      })
      use logical_json <- result.try(
        decode.run(logical, wire.json_value_decoder())
        |> result.map_error(fn(_) {
          InvalidPackedPayload("decoded runtime message is not JSON")
        }),
      )
      let representative =
        SequencedDocumentMessage(
          ..envelope.message,
          message_type: "op",
          contents: logical,
        )
      finish(state, representative, logical, logical_json)
    }
    Some(format) -> Error(UnsupportedCompression(format))
  }
}

fn finish(
  state: State,
  representative: SequencedDocumentMessage,
  contents: Dynamic,
  json_contents: Json,
) -> Result(Step, Error) {
  use metadata <- result.try(case representative.metadata {
    None -> Ok(None)
    Some(value) ->
      decode.run(value, wire.json_value_decoder())
      |> result.map(Some)
      |> result.map_error(fn(_) {
        InvalidPackedPayload("operation metadata is not JSON")
      })
  })
  use batch <- result.try(
    fluid_container.decode(json_contents, metadata)
    |> result.map_error(fn(error) {
      case error {
        fluid_container.UnsupportedCompression(_) ->
          InvalidPackedPayload("nested compression is not supported")
        _ -> ContainerFailure(error)
      }
    }),
  )
  use _ <- result.try(
    fluid_container.validate_profile_batch(batch)
    |> result.map_error(ContainerFailure),
  )
  Ok(Step(
    state,
    Complete(
      SequencedDocumentMessage(..representative, contents: contents),
      batch,
    ),
  ))
}

fn message_type_decoder() -> decode.Decoder(String) {
  use message_type <- decode.field("type", decode.string)
  decode.success(message_type)
}

fn chunk_decoder() -> decode.Decoder(Chunk) {
  use chunk <- decode.field("contents", chunk_contents_decoder())
  decode.success(chunk)
}

fn chunk_contents_decoder() -> decode.Decoder(Chunk) {
  use id <- decode.field("chunkId", decode.int)
  use total <- decode.field("totalChunks", decode.int)
  use contents <- decode.field("contents", decode.string)
  use original_type <- decode.optional_field(
    "originalType",
    None,
    decode.map(decode.string, Some),
  )
  use original_compression <- decode.optional_field(
    "originalCompression",
    None,
    decode.map(decode.string, Some),
  )
  use original_metadata <- decode.optional_field(
    "originalMetadata",
    None,
    decode.map(decode.dynamic, Some),
  )
  decode.success(Chunk(
    id,
    total,
    contents,
    original_type,
    original_compression,
    original_metadata,
  ))
}

fn packed_decoder() -> decode.Decoder(String) {
  use packed <- decode.field("packedContents", decode.string)
  decode.success(packed)
}

fn nested_compression_decoder() -> decode.Decoder(Option(String)) {
  use compression <- decode.optional_field(
    "compression",
    None,
    decode.map(decode.string, Some),
  )
  decode.success(compression)
}

fn has_packed_contents(contents: Dynamic) -> Bool {
  decode.run(contents, packed_presence_decoder())
  |> result.unwrap(False)
}

fn packed_presence_decoder() -> decode.Decoder(Bool) {
  use present <- decode.optional_field(
    "packedContents",
    False,
    decode.map(decode.dynamic, fn(_) { True }),
  )
  decode.success(present)
}

fn has_nested_compression(contents: Dynamic) -> Result(Bool, Nil) {
  case decode.run(contents, nested_compression_decoder()) {
    Ok(Some(_)) -> Ok(True)
    Error(_) -> Error(Nil)
    Ok(None) ->
      case decode.run(contents, message_type_decoder()) {
        Ok("component") ->
          case
            decode.run(
              contents,
              decode.at(["contents"], nested_compression_decoder()),
            )
          {
            Ok(Some(_)) -> Ok(True)
            Ok(None) -> Ok(False)
            Error(_) -> Error(Nil)
          }
        Ok(_) -> Ok(False)
        Error(_) -> Error(Nil)
      }
  }
}

fn map_lz4_error(error: lz4.Error) -> Error {
  case error {
    lz4.OutputLimitExceeded -> LimitExceeded("decoded payload")
    lz4.InvalidChecksum ->
      InvalidPackedPayload("compressed payload has an invalid checksum")
    lz4.UnsupportedFrameFeature(feature) ->
      InvalidPackedPayload("unsupported LZ4 frame feature: " <> feature)
    lz4.InvalidFrame -> InvalidPackedPayload("invalid LZ4 frame")
    lz4.InvalidMatch -> InvalidPackedPayload("invalid LZ4 match")
  }
}

fn check_packed_limit(limits: Limits, bytes: Int) -> Result(Nil, Error) {
  case bytes <= limits.max_packed_bytes {
    True -> Ok(Nil)
    False -> Error(LimitExceeded("packed payload"))
  }
}

fn check_buffered_limit(limits: Limits, bytes: Int) -> Result(Nil, Error) {
  case bytes <= limits.max_buffered_bytes {
    True -> Ok(Nil)
    False -> Error(LimitExceeded("buffered chunks"))
  }
}

fn check_stream_limit(limits: Limits, count: Int) -> Result(Nil, Error) {
  case count <= limits.max_streams {
    True -> Ok(Nil)
    False -> Error(LimitExceeded("open chunk streams"))
  }
}

fn check_chunk_count(limits: Limits, count: Int) -> Result(Nil, Error) {
  case count > 0 && count <= limits.max_chunks {
    True -> Ok(Nil)
    False -> Error(LimitExceeded("chunks per stream"))
  }
}
