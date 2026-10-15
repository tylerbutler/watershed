import gleam/json
import gleam/list
import gleam/option.{None, Some}
import startest/expect
import watershed/runtime_core
import watershed/tree/client_protocol
import watershed/tree/schema
import watershed/tree/types.{
  ArrayValue, BooleanValue, MapValue, NullValue, NumberValue, ObjectValue,
  StringValue,
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

pub fn shared_tree_client_runtime_state_evidence_is_document_scoped_test() -> Nil {
  client_protocol.decode_request(
    "{\"requestId\":1,\"command\":\"runtime-state-evidence\"}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(1, client_protocol.RuntimeStateEvidence)),
  )
  client_protocol.decode_request(
    "{\"requestId\":1,\"command\":\"runtime-state-evidence\",\"tree\":\"selected\"}",
  )
  |> expect.to_be_error()
  Nil
}

pub fn shared_tree_client_decodes_named_native_objects_test() -> Nil {
  let string_schema =
    "{\"version\":2,\"nodes\":{\"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}}},\"root\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]}}"
  let assert Ok(stored) = schema.stored_from_string(string_schema)
  let assert Ok(view) = schema.view_from_string(string_schema)
  client_protocol.decode_request(
    "{\"requestId\":1,\"command\":\"create-data-store\",\"name\":\"secondary\"}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(1, client_protocol.CreateDataStore("secondary"))),
  )
  client_protocol.decode_request(
    "{\"requestId\":2,\"command\":\"root-map\",\"name\":\"bootstrap\"}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(2, client_protocol.RootMap("bootstrap"))),
  )
  client_protocol.decode_request(
    "{\"requestId\":3,\"command\":\"data-store-root\",\"store\":\"secondary\",\"name\":\"entry\"}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(
      3,
      client_protocol.DataStoreRoot("secondary", "entry"),
    )),
  )
  client_protocol.decode_request(
    "{\"requestId\":4,\"command\":\"create-map\",\"store\":\"secondary\",\"name\":\"target-map\"}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(
      4,
      client_protocol.CreateMap("target-map", Some("secondary")),
    )),
  )
  client_protocol.decode_request(
    "{\"requestId\":5,\"command\":\"open-map\",\"name\":\"opened\",\"handle\":{\"type\":\"__fluid_handle__\",\"url\":\"/B/child\"}}",
  )
  |> expect.to_be_ok()
  client_protocol.decode_request(
    "{\"requestId\":6,\"command\":\"shared-map-set\",\"name\":\"target-map\",\"key\":\"tree\",\"value\":{\"type\":\"__fluid_handle__\",\"url\":\"/B/child\"}}",
  )
  |> expect.to_be_ok()
  client_protocol.decode_request(
    "{\"requestId\":7,\"command\":\"create-tree\",\"store\":\"secondary\",\"name\":\"target-tree\",\"schema\":"
    <> string_schema
    <> ",\"initialRoot\":{\"kind\":\"string\",\"value\":\"start\"},\"view\":"
    <> string_schema
    <> "}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(
      7,
      client_protocol.CreateTree(
        "target-tree",
        Some("secondary"),
        stored,
        StringValue("start"),
        view,
      ),
    )),
  )
  client_protocol.decode_request(
    "{\"requestId\":8,\"command\":\"open-tree\",\"name\":\"selected\",\"handle\":{\"type\":\"__fluid_handle__\",\"url\":\"/B/child\"},\"view\":"
    <> string_schema
    <> "}",
  )
  |> expect.to_be_ok()
  client_protocol.decode_request(
    "{\"requestId\":9,\"command\":\"read\",\"tree\":\"selected\",\"path\":[]}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(
      9,
      client_protocol.SelectedTree("selected", client_protocol.Read([])),
    )),
  )
}

pub fn shared_tree_client_decodes_alias_claim_test() {
  client_protocol.decode_request(
    "{\"requestId\":1,\"command\":\"try-set-alias\",\"store\":\"secondary\",\"alias\":\"public\"}",
  )
  |> expect.to_be_ok()
  Nil
}

pub fn shared_tree_client_rejects_bad_native_object_commands_test() -> Nil {
  list.each(
    [
      "{\"requestId\":1,\"command\":\"create-data-store\",\"name\":\"\"}",
      "{\"requestId\":2,\"command\":\"data-store-root\",\"store\":\"secondary\",\"name\":\"\"}",
      "{\"requestId\":3,\"command\":\"create-map\",\"name\":\"map\",\"store\":\"\"}",
      "{\"requestId\":4,\"command\":\"open-map\",\"name\":\"map\",\"handle\":{\"type\":\"wrong\",\"url\":\"/B/child\"}}",
      "{\"requestId\":5,\"command\":\"shared-map-get\",\"name\":\"map\"}",
      "{\"requestId\":6,\"command\":\"create-tree\",\"name\":\"tree\"}",
      "{\"requestId\":7,\"command\":\"open-tree\",\"name\":\"tree\",\"handle\":{\"type\":\"__fluid_handle__\",\"url\":\"relative\"},\"view\":{}}",
      "{\"requestId\":8,\"command\":\"read\",\"tree\":\"\",\"path\":[]}",
    ],
    fn(raw) { client_protocol.decode_request(raw) |> expect.to_be_error() },
  )
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
    [],
    json.object([]),
    None,
    None,
    None,
  )
  |> json.to_string
  |> expect.to_equal(
    "{\"root\":{\"present\":true,\"value\":{\"kind\":\"object\",\"schemaId\":\"org.watershed.Root\",\"fields\":[[\"title\",{\"kind\":\"string\",\"value\":\"hello\"}],[\"note\",{\"kind\":\"null\"}]]}},\"values\":{\"title\":{\"present\":true,\"value\":{\"kind\":\"string\",\"value\":\"hello\"}}},\"events\":[{\"local\":true}],\"commits\":[],\"history\":{}}",
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

pub fn shared_tree_client_decodes_array_commands_test() -> Nil {
  client_protocol.decode_request(
    "{\"requestId\":1,\"command\":\"array-get\",\"path\":[\"items\"],\"index\":2}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(1, client_protocol.ArrayGet(["items"], 2))),
  )
  client_protocol.decode_request(
    "{\"requestId\":2,\"command\":\"array-values\",\"path\":[\"byKey\",\"0\"]}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(2, client_protocol.ArrayValues(["byKey", "0"]))),
  )
  client_protocol.decode_request(
    "{\"requestId\":3,\"command\":\"array-insert\",\"path\":[\"items\"],\"index\":1,\"values\":[{\"kind\":\"array\",\"schemaId\":\"org.example.Items\",\"elements\":[{\"kind\":\"string\",\"value\":\"nested\"}]}]}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(
      3,
      client_protocol.ArrayInsert(["items"], 1, [
        ArrayValue("org.example.Items", [StringValue("nested")]),
      ]),
    )),
  )
  client_protocol.decode_request(
    "{\"requestId\":4,\"command\":\"array-remove\",\"path\":[\"items\"],\"start\":1,\"end\":3}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(4, client_protocol.ArrayRemove(["items"], 1, 3))),
  )
  client_protocol.decode_request(
    "{\"requestId\":7,\"command\":\"array-move\",\"sourcePath\":[\"left\"],\"sourceStart\":1,\"sourceEnd\":3,\"destinationPath\":[\"byKey\",\"0\"],\"destinationGap\":0}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(
      7,
      client_protocol.ArrayMove(["left"], 1, 3, ["byKey", "0"], 0),
    )),
  )
  client_protocol.decode_request(
    "{\"requestId\":8,\"command\":\"read\",\"path\":[\"byKey\",\"\"]}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(8, client_protocol.Read(["byKey", ""]))),
  )
}

pub fn shared_tree_client_decodes_constrained_array_remove_test() -> Nil {
  client_protocol.decode_request(
    "{\"requestId\":9,\"command\":\"constrained-array-remove\",\"targetPath\":[\"left\",\"0\"],\"path\":[\"right\"],\"start\":0,\"end\":1}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(
      9,
      client_protocol.ConstrainedArrayRemove(["left", "0"], ["right"], 0, 1),
    )),
  )
}

pub fn shared_tree_client_decodes_transaction_test() -> Nil {
  client_protocol.decode_request(
    "{\"requestId\":11,\"command\":\"transaction\",\"constraints\":[{\"type\":\"nodeInDocument\",\"path\":[\"items\",\"0\"]}],\"edits\":[{\"op\":\"array-remove\",\"path\":[\"right\"],\"start\":0,\"end\":1},{\"op\":\"transaction\",\"constraints\":[],\"edits\":[{\"op\":\"array-insert\",\"path\":[\"left\"],\"index\":0,\"values\":[{\"kind\":\"string\",\"value\":\"a\"}]}],\"result\":\"abort\"}],\"result\":\"commit\"}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(
      11,
      client_protocol.Transaction(client_protocol.TransactionScope(
        constraints: [["items", "0"]],
        edits: [
          client_protocol.TransactionArrayRemove(["right"], 0, 1),
          client_protocol.TransactionNested(client_protocol.TransactionScope(
            constraints: [],
            edits: [
              client_protocol.TransactionArrayInsert(["left"], 0, [
                StringValue("a"),
              ]),
            ],
            result: client_protocol.AbortScope,
          )),
        ],
        result: client_protocol.CommitScope,
      )),
    )),
  )
}

pub fn shared_tree_client_rejects_invalid_transactions_test() -> Nil {
  list.each(
    [
      "{\"requestId\":1,\"command\":\"transaction\",\"edits\":[],\"result\":\"commit\"}",
      "{\"requestId\":1,\"command\":\"transaction\",\"constraints\":[],\"result\":\"commit\"}",
      "{\"requestId\":1,\"command\":\"transaction\",\"constraints\":[],\"edits\":[],\"result\":\"rollback\"}",
      "{\"requestId\":1,\"command\":\"transaction\",\"constraints\":[{\"type\":\"nodeExists\",\"path\":[]}],\"edits\":[],\"result\":\"commit\"}",
      "{\"requestId\":1,\"command\":\"transaction\",\"constraints\":[{\"type\":\"nodeInDocument\"}],\"edits\":[],\"result\":\"commit\"}",
      "{\"requestId\":1,\"command\":\"transaction\",\"constraints\":[],\"edits\":[{\"op\":\"undo\"}],\"result\":\"commit\"}",
      "{\"requestId\":1,\"command\":\"transaction\",\"constraints\":[],\"edits\":[{\"op\":\"array-remove\",\"path\":[],\"start\":0,\"end\":-1}],\"result\":\"commit\"}",
    ],
    fn(raw) { client_protocol.decode_request(raw) |> expect.to_be_error() },
  )
}

pub fn shared_tree_client_encodes_transaction_result_test() -> Nil {
  client_protocol.encode_transaction_result(
    client_protocol.TransactionObservation(
      outcome: "committed",
      constraints: [["items", "0"]],
      edits_applied: 1,
      observed_tree: client_protocol.encode_read(Some(StringValue("inside"))),
      nested: [
        client_protocol.TransactionObservation(
          outcome: "aborted",
          constraints: [],
          edits_applied: 1,
          observed_tree: client_protocol.encode_read(None),
          nested: [],
        ),
      ],
    ),
    [json.object([#("kind", json.string("data"))])],
    Some("revision-1"),
    1,
    client_protocol.encode_read(Some(StringValue("after"))),
  )
  |> json.to_string
  |> expect.to_equal(
    "{\"outcome\":\"committed\",\"callback\":{\"outcome\":\"committed\",\"constraints\":[[\"items\",\"0\"]],\"editsApplied\":1,\"observedTree\":{\"present\":true,\"value\":{\"kind\":\"string\",\"value\":\"inside\"}},\"nested\":[{\"outcome\":\"aborted\",\"constraints\":[],\"editsApplied\":1,\"observedTree\":{\"present\":false},\"nested\":[]}]},\"events\":[{\"kind\":\"data\"}],\"commitRevision\":\"revision-1\",\"outboundCount\":1,\"tree\":{\"present\":true,\"value\":{\"kind\":\"string\",\"value\":\"after\"}}}",
  )
}

pub fn shared_tree_client_rejects_invalid_array_commands_test() -> Nil {
  list.each(
    [
      "{\"requestId\":1,\"command\":\"array-get\",\"path\":[],\"index\":-1}",
      "{\"requestId\":1,\"command\":\"array-get\",\"path\":[],\"index\":9007199254740992}",
      "{\"requestId\":1,\"command\":\"array-get\",\"path\":[],\"index\":1.5}",
      "{\"requestId\":1,\"command\":\"array-insert\",\"path\":[],\"index\":0}",
      "{\"requestId\":1,\"command\":\"array-insert\",\"path\":[],\"index\":0,\"values\":{}}",
      "{\"requestId\":1,\"command\":\"array-remove\",\"path\":[],\"start\":0}",
      "{\"requestId\":1,\"command\":\"array-remove\",\"path\":[],\"start\":0,\"end\":-1}",
      "{\"requestId\":1,\"command\":\"array-move\",\"sourcePath\":[],\"sourceStart\":0,\"sourceEnd\":1,\"destinationPath\":[]}",
      "{\"requestId\":1,\"command\":\"array-move\",\"sourcePath\":[],\"sourceStart\":0,\"sourceEnd\":1,\"destinationPath\":[],\"destinationGap\":9007199254740992}",
    ],
    fn(raw) { client_protocol.decode_request(raw) |> expect.to_be_error() },
  )
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

pub fn shared_tree_client_decodes_schema_commands_test() -> Nil {
  client_protocol.decode_request(
    "{\"requestId\":6,\"command\":\"schema-compatibility\",\"view\":\"optional\"}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(
      6,
      client_protocol.SchemaCompatibility("optional"),
    )),
  )
  client_protocol.decode_request(
    "{\"requestId\":7,\"command\":\"schema-upgrade\",\"view\":\"optional\"}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(7, client_protocol.SchemaUpgrade("optional"))),
  )
  client_protocol.decode_request(
    "{\"requestId\":8,\"command\":\"open-view\",\"view\":\"v1\"}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(8, client_protocol.OpenView("v1"))),
  )
  list.each(
    [
      "{\"requestId\":6,\"command\":\"schema-compatibility\"}",
      "{\"requestId\":7,\"command\":\"schema-upgrade\",\"view\":\"\"}",
      "{\"requestId\":8,\"command\":\"open-view\",\"view\":2}",
    ],
    fn(raw) { client_protocol.decode_request(raw) |> expect.to_be_error() },
  )
  Nil
}

pub fn shared_tree_client_decodes_revertible_status_test() -> Nil {
  client_protocol.decode_request(
    "{\"requestId\":9,\"op\":\"revertibleStatus\",\"name\":\"edit\"}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(9, client_protocol.RevertibleStatus("edit"))),
  )
  Nil
}

pub fn shared_tree_client_decodes_local_branch_commands_test() -> Nil {
  client_protocol.decode_request(
    "{\"requestId\":10,\"op\":\"fork\",\"source\":\"main\",\"name\":\"draft\"}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(10, client_protocol.Fork("main", "draft"))),
  )
  client_protocol.decode_request(
    "{\"requestId\":11,\"op\":\"branchEdit\",\"branch\":\"draft\",\"edit\":{\"kind\":\"object-set\",\"value\":\"draft\"}}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(
      11,
      client_protocol.BranchEditCommand(
        "draft",
        client_protocol.BranchSet(["title"], StringValue("draft")),
      ),
    )),
  )
  client_protocol.decode_request(
    "{\"requestId\":111,\"op\":\"branchEdit\",\"branch\":\"draft\",\"edit\":{\"kind\":\"object-set\",\"path\":[\"rating\"],\"value\":5}}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(
      111,
      client_protocol.BranchEditCommand(
        "draft",
        client_protocol.BranchSet(["rating"], NumberValue(5.0)),
      ),
    )),
  )
  client_protocol.decode_request(
    "{\"requestId\":12,\"op\":\"rebaseBranch\",\"source\":\"draft\",\"target\":\"main\"}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(
      12,
      client_protocol.RebaseBranch("draft", "main"),
    )),
  )
  client_protocol.decode_request(
    "{\"requestId\":13,\"op\":\"mergeBranch\",\"target\":\"main\",\"source\":\"draft\",\"dispose\":true}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(
      13,
      client_protocol.MergeBranch("main", "draft", True),
    )),
  )
  client_protocol.decode_request(
    "{\"requestId\":14,\"op\":\"disposeBranch\",\"name\":\"draft\"}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(14, client_protocol.DisposeBranch("draft"))),
  )
  client_protocol.decode_request(
    "{\"requestId\":15,\"op\":\"retainLastLocalCommit\",\"name\":\"edit\",\"branch\":\"draft\"}",
  )
  |> expect.to_equal(
    Ok(client_protocol.Request(
      15,
      client_protocol.BranchRetainLastLocalCommit("draft", "edit"),
    )),
  )
  client_protocol.decode_request(
    "{\"requestId\":16,\"op\":\"branchEdit\",\"branch\":\"draft\",\"edit\":{\"kind\":\"object-set\",\"path\":\"title\",\"value\":\"draft\"}}",
  )
  |> expect.to_be_error()
  Nil
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

pub fn shared_tree_client_extracts_action_revision_evidence_test() -> Nil {
  let history =
    json.object([
      #(
        "pending",
        json.array(
          [
            json.object([
              #("revision", json.string("pending-1")),
              #("originatorId", json.string("local")),
            ]),
            json.object([
              #("revision", json.string("pending-2")),
              #("originatorId", json.string("local")),
            ]),
          ],
          fn(value) { value },
        ),
      ),
      #(
        "trunk",
        json.array(
          [
            json.object([
              #(
                "commit",
                json.object([
                  #("revision", json.string("accepted-1")),
                  #("originatorId", json.string("peer")),
                ]),
              ),
            ]),
          ],
          fn(value) { value },
        ),
      ),
    ])
  client_protocol.history_revisions(history)
  |> expect.to_equal(["accepted-1", "pending-1", "pending-2"])
  client_protocol.history_commit_ids(history)
  |> expect.to_equal([
    #("accepted-1", "peer"),
    #("pending-1", "local"),
    #("pending-2", "local"),
  ])
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
