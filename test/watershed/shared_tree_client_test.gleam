import gleam/json
import gleam/list
import gleam/option.{None, Some}
import startest/expect
import watershed/runtime_core
import watershed/tree/client_protocol
import watershed/tree/types.{
  BooleanValue, NullValue, NumberValue, ObjectValue, StringValue,
}

pub fn shared_tree_client_rejects_unknown_command_test() -> Nil {
  client_protocol.decode_request(
    "{\"requestId\":1,\"command\":\"create-tree\"}",
  )
  |> expect.to_be_error()
  client_protocol.decode_request(
    "{\"requestId\":9007199254740992,\"command\":\"checkpoint\"}",
  )
  |> expect.to_be_error()
  Nil
}

pub fn shared_tree_client_preserves_absence_and_null_test() -> Nil {
  client_protocol.encode_read(None)
  |> json.to_string
  |> expect.to_equal("{\"present\":false}")
  client_protocol.encode_read(Some(NullValue))
  |> json.to_string
  |> expect.to_equal("{\"present\":true,\"value\":{\"kind\":\"null\"}}")
}

pub fn shared_tree_client_decodes_ordered_object_and_rejects_duplicates_test() -> Nil {
  client_protocol.decode_request(
    "{\"requestId\":3,\"command\":\"set\",\"path\":[\"point\"],\"value\":{\"kind\":\"object\",\"schemaId\":\"org.example.Point\",\"fields\":[[\"x\",{\"kind\":\"string\",\"value\":\"a\"}],[\"note\",{\"kind\":\"null\"}]]}}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(
      3,
      client_protocol.Set(
        ["point"],
        ObjectValue("org.example.Point", [
          #("x", StringValue("a")),
          #("note", NullValue),
        ]),
      ),
    )),
  )
  client_protocol.decode_request(
    "{\"requestId\":3,\"command\":\"set\",\"path\":[\"point\"],\"value\":{\"kind\":\"object\",\"schemaId\":\"org.example.Point\",\"fields\":[[\"x\",{\"kind\":\"null\"}],[\"x\",{\"kind\":\"null\"}]]}}",
  )
  |> expect.to_be_error()
  Nil
}

pub fn shared_tree_client_decodes_every_value_and_rejects_bad_input_test() -> Nil {
  list.each(
    [
      #("{\"kind\":\"string\",\"value\":\"x\"}", StringValue("x")),
      #("{\"kind\":\"number\",\"value\":2.5}", NumberValue(2.5)),
      #("{\"kind\":\"number\",\"value\":2}", NumberValue(2.0)),
      #("{\"kind\":\"boolean\",\"value\":true}", BooleanValue(True)),
      #("{\"kind\":\"null\"}", NullValue),
    ],
    fn(entry) {
      let #(raw, expected) = entry
      let request =
        "{\"requestId\":7,\"command\":\"set\",\"path\":[\"title\"],\"value\":"
        <> raw
        <> "}"
      client_protocol.decode_request(request)
      |> expect.to_equal(
        Ok(client_protocol.Request(7, client_protocol.Set(["title"], expected))),
      )
    },
  )
  list.each(
    [
      "{\"requestId\":7,\"command\":\"set\",\"path\":[\"title\"],\"value\":{\"kind\":\"surprise\"}}",
      "{\"requestId\":7,\"command\":\"set\",\"path\":[\"title\"],\"value\":{\"kind\":\"number\",\"value\":\"two\"}}",
      "{\"requestId\":7,\"command\":\"read\",\"path\":[\"\"]}",
      "{\"requestId\":7,\"command\":\"clear\",\"path\":[2]}",
      "{\"requestId\":-1,\"command\":\"checkpoint\"}",
      "{\"requestId\":7,\"command\":\"await-synced\",\"minimumSequenceNumber\":-1}",
      "{\"requestId\":7,\"command\":\"set\",\"path\":[\"point\"],\"value\":{\"kind\":\"object\",\"schemaId\":\"\",\"fields\":[]}}",
      "{",
    ],
    fn(raw) { client_protocol.decode_request(raw) |> expect.to_be_error() },
  )
  Nil
}

pub fn shared_tree_client_correlates_success_and_error_test() -> Nil {
  let observation =
    runtime_core.ConnectionObservation(
      phase: "ready",
      client_id: Some("session"),
      sequence_number: Some(12),
      in_flight_count: 0,
      pending_tree_count: 0,
      synced: True,
      error: None,
    )
  client_protocol.encode_response(client_protocol.Response(
    Some(9),
    Ok(client_protocol.encode_read(None)),
    observation,
  ))
  |> json.to_string
  |> expect.to_equal(
    "{\"requestId\":9,\"sequenceNumber\":12,\"observation\":{\"phase\":\"ready\",\"synced\":true,\"inFlightCount\":0,\"pendingTreeCount\":0,\"clientId\":\"session\",\"error\":null},\"ok\":true,\"result\":{\"present\":false}}",
  )
  client_protocol.encode_response(client_protocol.Response(
    None,
    Error(client_protocol.ProtocolError(
      "invalid-command",
      "decode",
      "malformed JSON",
    )),
    observation,
  ))
  |> json.to_string
  |> expect.to_equal(
    "{\"requestId\":null,\"sequenceNumber\":12,\"observation\":{\"phase\":\"ready\",\"synced\":true,\"inFlightCount\":0,\"pendingTreeCount\":0,\"clientId\":\"session\",\"error\":null},\"ok\":false,\"error\":{\"code\":\"invalid-command\",\"operation\":\"decode\",\"message\":\"malformed JSON\"}}",
  )
  Nil
}

pub fn shared_tree_client_rejects_invalid_descriptor_test() -> Nil {
  client_protocol.decode_descriptor("{}") |> expect.to_be_error()
  client_protocol.decode_descriptor(
    "{\"protocolVersion\":2,\"runId\":\"run\",\"documentId\":\"doc\",\"tenant\":\"fluid\",\"socketUrl\":\"ws://127.0.0.1:7777/socket/websocket?vsn=2.0.0\",\"host\":\"127.0.0.1\",\"port\":7777,\"viewSchema\":{}}",
  )
  |> expect.to_be_error()
  Nil
}
