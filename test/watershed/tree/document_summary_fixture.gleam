import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import spillway/types as spillway_types
import watershed/channel
import watershed/fluid_ids
import watershed/runtime_core
import watershed/tree/runtime_fixture
import watershed/tree/types.{
  type TreeValue, BooleanValue, NullValue, NumberValue, ObjectValue, StringValue,
}
import watershed/wire
import watershed/wire/fluid_document
import watershed/wire/socket

pub fn run(input: Json) -> Result(Json, String) {
  use snapshot <- result.try(
    json.parse(
      json.to_string(input),
      decode.at(["replayInput", "snapshotAtS"], wire.json_value_decoder()),
    )
    |> result.map_error(string.inspect),
  )
  use reference <- result.try(
    json.parse(
      json.to_string(input),
      decode.at(["replayInput", "summaryReferenceSequenceNumber"], decode.int),
    )
    |> result.map_error(string.inspect),
  )
  use publication <- result.try(
    json.parse(
      json.to_string(input),
      decode.at(["replayInput", "publicationSequenceNumber"], decode.int),
    )
    |> result.map_error(string.inspect),
  )
  use prefix <- result.try(messages(input, "summaryToPublicationMessages"))
  use later <- result.try(messages(input, "laterTailMessages"))
  use document <- result.try(runtime_fixture.read_snapshot(snapshot))
  use session <- result.try(
    fluid_ids.session_id("70000000-0000-4000-8000-000000000007")
    |> result.map_error(string.inspect),
  )
  use view <- result.try(
    fluid_ids.stable_id("60000000-0000-4000-8000-000000000006")
    |> result.map_error(string.inspect),
  )
  use summary <- result.try(
    fluid_document.decode(document, None, session, view)
    |> result.map_error(string.inspect),
  )
  use _ <- result.try(require(
    fluid_document.sequence_number(summary) == reference,
    "snapshot reference differs from protocol attributes",
  ))
  use address <- result.try(tree_address(summary))
  let connected = runtime_fixture.connected("reader", [], reference)
  use bootstrapped <- result.try(
    runtime_core.bootstrap_document(connected, summary)
    |> result.map_error(string.inspect),
  )
  use core <- result.try(complete(bootstrapped))
  use _ <- result.try(
    runtime_core.root_channel_address(core)
    |> result.map_error(string.inspect),
  )
  use initial <- result.try(root(core, address))
  use core <- result.try(replay(core, prefix))
  use _ <- result.try(require(
    core.last_seen_sequence_number == publication,
    "publication prefix has the wrong checkpoint",
  ))
  use at_publication <- result.try(root(core, address))
  use captured <- result.try(
    runtime_core.capture_summary(core) |> result.map_error(string.inspect),
  )
  use _ <- result.try(require(
    fluid_document.sequence_number(captured) == publication,
    "captured summary moved from its sequenced point",
  ))
  use core <- result.try(replay(core, later))
  use final <- result.try(root(core, address))
  Ok(
    json.object([
      #(
        "observations",
        json.array(
          [
            json.object([
              #("checkpoint", json.string("summary-captured")),
              #("sequenceNumber", json.int(reference)),
              #("root", initial),
            ]),
            json.object([
              #("checkpoint", json.string("replayed-through-publication")),
              #("sequenceNumber", json.int(publication)),
              #(
                "replayedSequenceNumbers",
                json.array(prefix, fn(message) {
                  json.int(message.sequence_number)
                }),
              ),
              #("root", at_publication),
            ]),
            json.object([
              #("checkpoint", json.string("later-edit-after-reload")),
              #("root", final),
            ]),
          ],
          fn(value) { value },
        ),
      ),
    ]),
  )
}

fn messages(
  input: Json,
  name: String,
) -> Result(List(spillway_types.SequencedDocumentMessage), String) {
  json.parse(
    json.to_string(input),
    decode.at(
      ["replayInput", name],
      decode.list(socket.sequenced_document_message_decoder()),
    ),
  )
  |> result.map_error(string.inspect)
}

fn tree_address(
  summary: fluid_document.DocumentSummary,
) -> Result(String, String) {
  let trees =
    list.flat_map(fluid_document.datastores(summary), fn(store) {
      list.flat_map(store.channels, fn(item) {
        case item.snapshot {
          channel.TreeSnapshot(_) -> [store.id <> "/" <> item.id]
          _ -> []
        }
      })
    })
  case trees {
    [address] -> Ok(address)
    _ -> Error("summary must contain one SharedTree channel")
  }
}

fn complete(
  value: runtime_core.Bootstrapped,
) -> Result(runtime_core.Core, String) {
  case value {
    runtime_core.Complete(core) -> Ok(core)
    runtime_core.MissingPrefix(_, _, _, _) ->
      Error("summary bootstrap has a missing prefix")
  }
}

fn replay(
  core: runtime_core.Core,
  messages: List(spillway_types.SequencedDocumentMessage),
) -> Result(runtime_core.Core, String) {
  list.try_fold(messages, core, fn(core, message) {
    runtime_core.handle_sequenced(core, message)
    |> result.map(fn(outcome) { outcome.0 })
    |> result.map_error(string.inspect)
  })
}

fn root(core: runtime_core.Core, address: String) -> Result(Json, String) {
  use value <- result.try(
    runtime_core.tree_read(core, address, [])
    |> result.map_error(string.inspect),
  )
  case value {
    Some(value) -> Ok(value_json(value))
    None -> Error("summary has no tree root")
  }
}

fn value_json(value: TreeValue) -> Json {
  case value {
    StringValue(value) -> json.string(value)
    NumberValue(value) -> json.float(value)
    BooleanValue(value) -> json.bool(value)
    NullValue -> json.null()
    ObjectValue(_, fields) ->
      json.object(
        list.map(fields, fn(entry) { #(entry.0, value_json(entry.1)) }),
      )
    types.MapValue(_, _) ->
      panic as { "map values are not supported by summary fixtures" }
  }
}

fn require(value: Bool, detail: String) -> Result(Nil, String) {
  case value {
    True -> Ok(Nil)
    False -> Error(detail)
  }
}
