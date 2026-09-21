import gleam/json
import gleam/option.{Some}
import gleam/result
import gleam/string
import watershed/wire/socket

@target(erlang)
import aquamarine
@target(erlang)
import aquamarine/channel.{type Channel}
@target(erlang)
import aquamarine/phoenix
@target(erlang)
import envoy
@target(erlang)
import gleam/dynamic/decode
@target(erlang)
import gleam/int
@target(erlang)
import gleam/io
@target(erlang)
import watershed/wire

pub fn observation(
  payload: String,
  document: String,
  summary_handle: String,
) -> Result(String, String) {
  use connected <- result.try(
    json.parse(payload, socket.connected_message_decoder())
    |> result.map_error(fn(error) {
      "Invalid connection response: " <> string.inspect(error)
    }),
  )
  case connected.checkpoint_sequence_number, connected.summary_context {
    Some(checkpoint), Some(summary)
      if connected.claims.document_id == document
      && connected.client_id != ""
      && summary.handle == summary_handle
    -> {
      json.object([
        #("clientId", json.string(connected.client_id)),
        #("checkpointSequenceNumber", json.int(checkpoint)),
        #("summaryHandle", json.string(summary.handle)),
        #("summarySequenceNumber", json.int(summary.sequence_number)),
      ])
      |> json.to_string
      |> Ok
    }
    _, _ ->
      Error("The connection does not identify the expected document summary")
  }
}

@target(erlang)
pub fn main() -> Nil {
  let assert Ok(host) = envoy.get("WATERSHED_TREE_HOST")
  let assert Ok(port_text) = envoy.get("WATERSHED_TREE_PORT")
  let assert Ok(port) = int.parse(port_text)
  let assert Ok(topic) = envoy.get("WATERSHED_TREE_TOPIC")
  let assert Ok(token) = envoy.get("WATERSHED_TREE_TOKEN")
  let assert Ok(payload_text) = envoy.get("WATERSHED_TREE_CONNECT")
  let assert Ok(payload) = json.parse(payload_text, decode.dynamic)
  let assert Ok(document) = envoy.get("WATERSHED_TREE_DOCUMENT")
  let assert Ok(summary_handle) = envoy.get("WATERSHED_TREE_SUMMARY")
  let assert Ok(channel) =
    aquamarine.connect(
      host: host,
      port: port,
      path: "/socket/websocket?vsn=2.0.0",
      topic: topic,
      payload: json.object([#("token", json.string(token))]),
      codec: phoenix.codec(),
    )
  let result = {
    use _ <- result.try(
      aquamarine.push(
        channel,
        "connect_document",
        wire.dynamic_to_json(payload),
      )
      |> result.map_error(string.inspect),
    )
    receive_connection(channel, document, summary_handle, 20)
  }
  let assert Ok(Nil) = aquamarine.close(channel)
  let assert Ok(observed) = result
  io.println("WATERSHED_TREE_TRANSPORT=" <> observed)
}

@target(erlang)
fn receive_connection(
  channel: Channel,
  document: String,
  summary_handle: String,
  remaining: Int,
) -> Result(String, String) {
  case remaining {
    0 -> Error("The service did not send a connection response")
    _ -> {
      use incoming <- result.try(
        aquamarine.receive(channel) |> result.map_error(string.inspect),
      )
      case incoming.event {
        "connect_document_success" ->
          observation(
            incoming.payload |> wire.dynamic_to_json |> json.to_string,
            document,
            summary_handle,
          )
        "op" | "signal" | "presence_state" | "presence_diff" ->
          receive_connection(channel, document, summary_handle, remaining - 1)
        event -> Error("Unexpected transport event: " <> event)
      }
    }
  }
}
