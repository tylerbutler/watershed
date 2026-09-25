import gleam/json
import gleam/list
import gleam/option.{None, Some}
import startest/expect
import watershed/runtime_core
import watershed/tree/client_protocol
import watershed/tree/types.{
  BooleanValue, MapValue, NullValue, NumberValue, ObjectValue, StringValue,
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

pub fn shared_tree_client_encodes_full_root_checkpoint_test() -> Nil {
  client_protocol.encode_checkpoint(
    client_protocol.encode_read(
      Some(
        ObjectValue("org.watershed.Root", [
          #("title", StringValue("hello")),
          #("note", NullValue),
        ]),
      ),
    ),
    [#("title", client_protocol.encode_read(Some(StringValue("hello"))))],
    [json.object([#("local", json.bool(True))])],
  )
  |> json.to_string
  |> expect.to_equal(
    "{\"root\":{\"present\":true,\"value\":{\"kind\":\"object\",\"schemaId\":\"org.watershed.Root\",\"fields\":[[\"title\",{\"kind\":\"string\",\"value\":\"hello\"}],[\"note\",{\"kind\":\"null\"}]]}},\"values\":{\"title\":{\"present\":true,\"value\":{\"kind\":\"string\",\"value\":\"hello\"}}},\"events\":[{\"local\":true}]}",
  )
}

pub fn shared_tree_client_encodes_structured_startup_error_test() -> Nil {
  client_protocol.encode_startup_error(
    "bootstrap-failed",
    "connect",
    "summary decode failed",
  )
  |> expect.to_equal(
    "{\"kind\":\"startup-error\",\"code\":\"bootstrap-failed\",\"operation\":\"connect\",\"message\":\"summary decode failed\"}",
  )
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

pub fn shared_tree_client_decodes_map_commands_test() -> Nil {
  client_protocol.decode_request(
    "{\"requestId\":1,\"command\":\"map-get\",\"path\":[\"items\"],\"key\":\"\"}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(1, client_protocol.MapGet(["items"], ""))),
  )
  client_protocol.decode_request(
    "{\"requestId\":2,\"command\":\"map-set\",\"path\":[\"items\"],\"key\":\"é\",\"value\":{\"kind\":\"map\",\"schemaId\":\"org.example.Map\",\"entries\":[[\"nested\",{\"kind\":\"string\",\"value\":\"x\"}]]}}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(
      2,
      client_protocol.MapSet(
        ["items"],
        "é",
        MapValue("org.example.Map", [#("nested", StringValue("x"))]),
      ),
    )),
  )
  client_protocol.decode_request(
    "{\"requestId\":3,\"command\":\"map-delete\",\"path\":[\"items\"],\"key\":\"a\"}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(3, client_protocol.MapDelete(["items"], "a"))),
  )
  client_protocol.decode_request(
    "{\"requestId\":4,\"command\":\"map-keys\",\"path\":[\"items\"]}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(4, client_protocol.MapKeys(["items"]))),
  )
  client_protocol.decode_request(
    "{\"requestId\":5,\"command\":\"map-entries\",\"path\":[\"items\"]}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(5, client_protocol.MapEntries(["items"]))),
  )
}

pub fn shared_tree_client_rejects_invalid_map_commands_test() -> Nil {
  list.each(
    [
      "{\"requestId\":1,\"command\":\"map-get\",\"path\":[\"items\"]}",
      "{\"requestId\":1,\"command\":\"map-get\",\"path\":[\"items\"],\"key\":1}",
      "{\"requestId\":1,\"command\":\"map-set\",\"path\":[\"items\"],\"key\":\"a\",\"value\":{\"kind\":\"map\",\"schemaId\":\"\",\"entries\":[]}}",
      "{\"requestId\":1,\"command\":\"map-set\",\"path\":[\"items\"],\"key\":\"a\",\"value\":{\"kind\":\"map\",\"schemaId\":\"org.example.Map\",\"entries\":[[\"x\",{\"kind\":\"null\"}],[\"x\",{\"kind\":\"null\"}]]}}",
      "{\"requestId\":1,\"command\":\"map-set\",\"path\":[\"items\"],\"key\":\"a\",\"value\":{\"kind\":\"map\",\"schemaId\":\"org.example.Map\",\"entries\":[[\"x\"]]}}",
    ],
    fn(raw) { client_protocol.decode_request(raw) |> expect.to_be_error() },
  )
}

pub fn shared_tree_client_encodes_map_results_canonically_test() -> Nil {
  client_protocol.encode_map_keys(["😀", "�", "a", ""])
  |> json.to_string
  |> expect.to_equal("[\"\",\"a\",\"�\",\"😀\"]")
  client_protocol.encode_map_entries([
    #("😀", NullValue),
    #("�", MapValue("org.example.Map", [#("", StringValue("x"))])),
  ])
  |> json.to_string
  |> expect.to_equal(
    "[[\"�\",{\"kind\":\"map\",\"schemaId\":\"org.example.Map\",\"entries\":[[\"\",{\"kind\":\"string\",\"value\":\"x\"}]]}],[\"😀\",{\"kind\":\"null\"}]]",
  )
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
