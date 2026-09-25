import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import startest/expect
import watershed/channel
import watershed/fluid_ids
import watershed/runtime_core
import watershed/tree/runtime_fixture
import watershed/tree/schema
import watershed/tree/types
import watershed/wire
import watershed/wire/fluid_document
import watershed/wire/fluid_summary

fn stored() -> schema.StoredSchema {
  let assert Ok(stored) =
    schema.stored_from_string(
      "{\"version\":2,\"nodes\":{
        \"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}},
        \"com.fluidframework.leaf.number\":{\"kind\":{\"leaf\":0}},
        \"com.fluidframework.leaf.boolean\":{\"kind\":{\"leaf\":2}},
        \"com.fluidframework.leaf.null\":{\"kind\":{\"leaf\":4}},
        \"creation.Point\":{\"kind\":{\"object\":{
          \"x\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.number\"]}
        }}},
        \"creation.Root\":{\"kind\":{\"object\":{
          \"title\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.string\"]},
          \"enabled\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.boolean\"]},
          \"marker\":{\"kind\":\"Value\",\"types\":[\"com.fluidframework.leaf.null\"]},
          \"note\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]},
          \"point\":{\"kind\":\"Value\",\"types\":[\"creation.Point\"]}
        }}}
      },\"root\":{\"kind\":\"Value\",\"types\":[\"creation.Root\"]}}",
    )
  stored
}

fn root() -> types.TreeValue {
  types.ObjectValue("creation.Root", [
    #("title", types.StringValue("Native")),
    #("enabled", types.BooleanValue(True)),
    #("marker", types.NullValue),
    #(
      "point",
      types.ObjectValue("creation.Point", [
        #("x", types.NumberValue(42.0)),
      ]),
    ),
  ])
}

fn identity() -> #(fluid_ids.SessionId, fluid_ids.StableId) {
  let assert Ok(session) =
    fluid_ids.session_id("10000000-0000-4000-8000-000000000001")
  let assert Ok(view) =
    fluid_ids.stable_id("20000000-0000-4000-8000-000000000002")
  #(session, view)
}

fn initial() -> fluid_document.DocumentSummary {
  let #(session, view) = identity()
  let assert Ok(summary) =
    fluid_document.initial_tree(stored(), Some(root()), session, view)
  summary
}

fn blob(tree: fluid_summary.SummaryEntry, path: String) -> json.Json {
  let assert Ok(fluid_summary.SummaryBlob(bytes)) =
    fluid_summary.resolve(
      fluid_summary.SummaryHandle(path, fluid_summary.BlobHandle),
      Some(tree),
    )
  let assert Ok(text) = bit_array.to_string(bytes)
  let assert Ok(value) = json.parse(text, wire.json_value_decoder())
  value
}

pub fn shared_tree_creation_round_trip_and_first_edit_test() {
  let created = initial()
  fluid_document.sequence_number(created) |> expect.to_equal(0)
  fluid_document.aliases(created) |> expect.to_equal([#("root", "A")])
  let assert Ok(encoded) = fluid_document.encode(created)
  let assert Ok(session) =
    fluid_ids.session_id("30000000-0000-4000-8000-000000000003")
  let assert Ok(view) =
    fluid_ids.stable_id("40000000-0000-4000-8000-000000000004")
  let assert Ok(loaded) = fluid_document.decode(encoded, None, session, view)
  let assert Ok(runtime_core.Complete(core)) =
    runtime_core.bootstrap_document(
      runtime_fixture.connected("reader", [], 0),
      loaded,
    )
  runtime_core.root_channel_address(core) |> expect.to_equal(Ok("A/root"))
  runtime_core.tree_read(core, "A/_C", [])
  |> expect.to_equal(Ok(Some(root())))
  runtime_core.tree_read(core, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(types.StringValue("Native"))))
  runtime_core.tree_read(core, "A/_C", ["note"])
  |> expect.to_equal(Ok(None))
  runtime_core.tree_read(core, "A/_C", ["marker"])
  |> expect.to_equal(Ok(Some(types.NullValue)))
  runtime_core.has_pending_tree(core) |> expect.to_be_false()
  let assert Ok(#(edited, _, outbound)) =
    runtime_core.submit_tree_edits(core, "A/_C", [
      types.SetField(["title"], types.StringValue("First edit")),
    ])
  list.length(outbound) |> expect.to_equal(1)
  runtime_core.tree_read(edited, "A/_C", ["title"])
  |> expect.to_equal(Ok(Some(types.StringValue("First edit"))))
}

pub fn shared_tree_creation_preserves_routing_and_empty_history_test() {
  let assert Ok(tree) = fluid_document.encode(initial())
  blob(tree, "/.aliases")
  |> json.to_string
  |> expect.to_equal("[[\"root\",\"A\"]]")
  let header = blob(tree, "/.channels/A/.channels/root/header")
  json.parse(
    json.to_string(header),
    decode.at(["content", "tree", "value", "url"], decode.string),
  )
  |> expect.to_equal(Ok("/A/_C"))
  let detached =
    blob(
      tree,
      "/.channels/A/.channels/_C/indexes/DetachedFieldIndex/DetachedFieldIndexBlob",
    )
  json.parse(json.to_string(detached), decode.at(["maxId"], decode.int))
  |> expect.to_equal(Ok(0))
  let gc = blob(tree, "/gc/__gc_root")
  json.parse(
    json.to_string(gc),
    decode.at(
      ["gcNodes", "/A/root", "outboundRoutes"],
      decode.list(decode.string),
    ),
  )
  |> expect.to_equal(Ok(["/A", "/A/_C"]))
  blob(tree, "/.idCompressor")
  |> json.to_string
  |> expect.to_equal("\"AAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\"")
}

pub fn shared_tree_creation_request_contains_app_and_code_not_protocol_test() {
  let assert Ok(body) = fluid_document.encode_create_request(initial())
  let raw = json.to_string(body)
  json.parse(raw, decode.at(["sequenceNumber"], decode.int))
  |> expect.to_equal(Ok(0))
  let assert Ok(names) =
    json.parse(
      raw,
      decode.at(
        ["summary", "entries"],
        decode.list(decode.at(["path"], decode.string)),
      ),
    )
  list.contains(names, ".protocol") |> expect.to_be_false()
  list.contains(names, ".app") |> expect.to_be_false()
  list.contains(names, ".channels") |> expect.to_be_true()
  list.contains(names, ".idCompressor") |> expect.to_be_true()
  json.parse(raw, decode.at(["enableDiscovery"], decode.bool))
  |> expect.to_equal(Ok(False))
  json.parse(
    raw,
    decode.at(
      ["values"],
      decode.list({
        use key <- decode.field(0, decode.string)
        use package <- decode.field(
          1,
          decode.at(["value", "package"], decode.string),
        )
        decode.success(#(key, package))
      }),
    ),
  )
  |> expect.to_equal(Ok([#("code", "watershed-shared-tree")]))
}

pub fn shared_tree_creation_invalid_initial_values_test() {
  let #(session, view) = identity()
  let assert types.ObjectValue(kind, fields) = root()
  let wrong_nested =
    types.ObjectValue(
      kind,
      list.map(fields, fn(field) {
        case field.0 {
          "point" -> #(
            "point",
            types.ObjectValue("creation.Point", [
              #("x", types.StringValue("not a number")),
            ]),
          )
          _ -> field
        }
      }),
    )
  list.each(
    [
      None,
      Some(types.NullValue),
      Some(types.ObjectValue("creation.Root", [])),
      Some(types.StringValue("wrong root")),
      Some(wrong_nested),
      Some(types.ObjectValue(kind, [#("unknown", types.NullValue), ..fields])),
      Some(
        types.ObjectValue(kind, [
          #("title", types.StringValue("duplicate")),
          ..fields
        ]),
      ),
      Some(types.ObjectValue(kind, [#("note", types.NullValue), ..fields])),
    ],
    fn(value) {
      fluid_document.initial_tree(stored(), value, session, view)
      |> result.is_error
      |> expect.to_be_true()
    },
  )
}

@target(javascript)
pub fn shared_tree_creation_rejects_nonfinite_initial_numbers_test() -> Nil {
  let #(session, view) = identity()
  let infinity = 1.7976931348623157e308 *. 2.0
  let assert types.ObjectValue(kind, fields) = root()
  list.each([infinity, 0.0 -. infinity, infinity -. infinity], fn(number) {
    let root =
      types.ObjectValue(
        kind,
        list.map(fields, fn(field) {
          case field.0 {
            "point" -> #(
              "point",
              types.ObjectValue("creation.Point", [
                #("x", types.NumberValue(number)),
              ]),
            )
            _ -> field
          }
        }),
      )
    fluid_document.initial_tree(stored(), Some(root), session, view)
    |> result.is_error
    |> expect.to_be_true()
  })
}

pub fn shared_tree_creation_optional_root_and_other_schema_test() {
  let assert Ok(stored) =
    schema.stored_from_string(
      "{\"version\":2,\"nodes\":{
        \"com.fluidframework.leaf.string\":{\"kind\":{\"leaf\":1}}
      },\"root\":{\"kind\":\"Optional\",\"types\":[\"com.fluidframework.leaf.string\"]}}",
    )
  let #(session, view) = identity()
  let assert Ok(summary) =
    fluid_document.initial_tree(stored, None, session, view)
  let assert Ok(encoded) = fluid_document.encode(summary)
  let assert Ok(_) = fluid_document.decode(encoded, None, session, view)
  Nil
}

pub fn shared_tree_creation_refuses_existing_checkpoint_test() {
  let assert Ok(summary) =
    fluid_document.native(5, 0, [], [
      #("watershed/root", channel.MapSnapshot([])),
    ])
  fluid_document.encode_create_request(summary)
  |> result.is_error
  |> expect.to_be_true()
}
