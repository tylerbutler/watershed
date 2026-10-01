import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import startest/expect
import watershed/fluid_ids
import watershed/tree/change_fixture_codec as fixture_codec
import watershed/tree/codec/field_batch
import watershed/tree/fixtures
import watershed/tree/identifier_fixture
import watershed/tree/schema
import watershed/tree/types.{
  ArrayValue, BooleanValue, MapValue, NullValue, NumberValue, ObjectValue,
  StringValue,
}
import watershed/wire

const map_type = "org.watershed.shared-tree.m2.DynamicMap"

const array_type = "org.watershed.shared-tree.m3.Items"

const array_map_type = "org.watershed.shared-tree.m3.ArrayMap"

const point_type = "org.watershed.shared-tree.m3.Point"

const points_type = "org.watershed.shared-tree.m3.Points"

const root_type = "org.watershed.shared-tree.m3.Root"

fn encoded_batch(shapes: List(json.Json), data: List(json.Json)) -> json.Json {
  json.object([
    #("version", json.int(2)),
    #("identifiers", json.array([], fn(value) { value })),
    #("shapes", json.array(shapes, fn(value) { value })),
    #("data", json.array(data, fn(value) { value })),
  ])
}

fn stream(values: List(json.Json)) -> json.Json {
  json.array(values, fn(value) { value })
}

fn identifier_batch(value: json.Json) -> json.Json {
  encoded_batch(
    [
      json.object([
        #(
          "c",
          json.object([
            #("type", json.string("com.fluidframework.leaf.string")),
            #("value", json.int(0)),
          ]),
        ),
      ]),
    ],
    [stream([json.int(0), value])],
  )
}

fn map_schema() -> schema.StoredSchema {
  let assert Ok(fixture) = fixtures.load("map-schema-content")
  let assert Ok(raw) =
    json.parse(
      json.to_string(fixture.input),
      decode.at(["schemas", "recursive"], decode.string),
    )
  let assert Ok(stored) = schema.stored_from_string(raw)
  stored
}

fn array_schema() -> schema.StoredSchema {
  let assert Ok(fixture) = fixtures.load("array-schema-content")
  let assert Ok(raw) =
    json.parse(
      json.to_string(fixture.input),
      decode.at(["schemas", "rootArray"], decode.string),
    )
  let assert Ok(stored) = schema.stored_from_string(raw)
  stored
}

pub fn shared_tree_codec_field_batch_uncompressed_string_test() {
  let fields = [[StringValue("native")]]
  let assert Ok(encoded) = field_batch.encode(fields)
  let assert Ok(decoded) = field_batch.decode(encoded)
  decoded |> expect.to_equal(fields)
}

pub fn shared_tree_codec_field_batch_decodes_literal_identifier_values_test() {
  [
    "",
    "customer-17",
    "11111111-1111-4111-8111-111111111111",
    "4b825dc6-5768-5c1e-9a66-9e0f9e2f3f45",
    "客户-🌊",
  ]
  |> list.each(fn(identifier) {
    let encoded =
      encoded_batch(
        [
          json.object([
            #(
              "c",
              json.object([
                #("type", json.string("com.fluidframework.leaf.string")),
                #("value", json.int(0)),
              ]),
            ),
          ]),
        ],
        [stream([json.int(0), json.string(identifier)])],
      )
    field_batch.decode(encoded)
    |> expect.to_equal(Ok([[StringValue(identifier)]]))
  })
}

pub fn shared_tree_codec_field_batch_keeps_identifier_table_separate_test() {
  let encoded =
    json.object([
      #("version", json.int(2)),
      #(
        "identifiers",
        json.array(["com.fluidframework.leaf.string"], json.string),
      ),
      #(
        "shapes",
        json.array(
          [
            json.object([
              #(
                "c",
                json.object([
                  #("type", json.int(0)),
                  #("value", json.int(0)),
                ]),
              ),
            ]),
          ],
          fn(value) { value },
        ),
      ),
      #(
        "data",
        json.array([stream([json.int(0), json.string("literal")])], fn(value) {
          value
        }),
      ),
    ])
  field_batch.decode(encoded)
  |> expect.to_equal(Ok([[StringValue("literal")]]))
}

pub fn shared_tree_codec_field_batch_requires_context_for_numeric_identifier_test() {
  let assert Error(types.UnsupportedFeature(location, _)) =
    field_batch.decode(identifier_batch(json.int(-1)))
  location |> expect.to_equal("fieldBatch.data[0].value")
}

pub fn shared_tree_codec_field_batch_decodes_message_identifier_test() {
  let sender_session = identifier_fixture.sender_session()
  let sender = fluid_ids.new(sender_session)
  let assert Ok(#(sender, local)) = fluid_ids.generate(sender)
  let assert Ok(stable) = fluid_ids.decompress(sender, local)
  let assert Ok(operation) = fluid_ids.to_op(sender, local)
  let #(sender, range) = fluid_ids.take_creation_range(sender)
  let assert Some(range) = range
  let assert Ok(receiver) =
    fluid_ids.new(identifier_fixture.receiver_session())
    |> fluid_ids.finalize(range)

  field_batch.decode_with_context(
    identifier_batch(json.int(fluid_ids.op_id_to_int(operation))),
    None,
    field_batch.MessageIds(receiver, sender_session),
  )
  |> expect.to_equal(
    Ok([
      [
        StringValue(fluid_ids.stable_id_to_string(stable)),
      ],
    ]),
  )

  let assert Ok(sender) = fluid_ids.finalize(sender, range)
  let assert Ok(operation) = fluid_ids.to_op(sender, local)
  field_batch.decode_with_context(
    identifier_batch(json.int(fluid_ids.op_id_to_int(operation))),
    None,
    field_batch.MessageIds(receiver, sender_session),
  )
  |> expect.to_equal(
    Ok([
      [
        StringValue(fluid_ids.stable_id_to_string(stable)),
      ],
    ]),
  )
}

pub fn shared_tree_codec_field_batch_rejects_unresolvable_message_identifier_test() {
  let sender_session = identifier_fixture.sender_session()
  let sender = fluid_ids.new(sender_session)
  let assert Ok(#(sender, local)) = fluid_ids.generate(sender)
  let assert Ok(operation) = fluid_ids.to_op(sender, local)
  let encoded = identifier_batch(json.int(fluid_ids.op_id_to_int(operation)))
  let receiver = fluid_ids.new(identifier_fixture.receiver_session())

  let assert Error(types.CorruptData(location, _)) =
    field_batch.decode_with_context(
      encoded,
      None,
      field_batch.MessageIds(receiver, sender_session),
    )
  location |> expect.to_equal("fieldBatch.data[0].value")

  let assert Ok(#(receiver, _)) = fluid_ids.generate(receiver)
  let assert Error(types.CorruptData(_, _)) =
    field_batch.decode_with_context(
      encoded,
      None,
      field_batch.MessageIds(receiver, sender_session),
    )

  let #(_, range) = fluid_ids.take_creation_range(sender)
  let assert Some(range) = range
  let assert Ok(wrong_origin_receiver) =
    fluid_ids.new(identifier_fixture.receiver_session())
    |> fluid_ids.finalize(range)
  let assert Error(types.CorruptData(_, _)) =
    field_batch.decode_with_context(
      encoded,
      None,
      field_batch.MessageIds(
        wrong_origin_receiver,
        identifier_fixture.receiver_session(),
      ),
    )
  Nil
}

pub fn shared_tree_codec_field_batch_decodes_summary_identifier_test() {
  let sender = fluid_ids.new(identifier_fixture.sender_session())
  let assert Ok(#(sender, local)) = fluid_ids.generate(sender)
  let assert Ok(stable) = fluid_ids.decompress(sender, local)
  let #(sender, range) = fluid_ids.take_creation_range(sender)
  let assert Some(range) = range
  let assert Ok(sender) = fluid_ids.finalize(sender, range)
  let assert Ok(operation) = fluid_ids.to_op(sender, local)

  field_batch.decode_with_context(
    identifier_batch(json.int(fluid_ids.op_id_to_int(operation))),
    None,
    field_batch.SummaryIds(sender),
  )
  |> expect.to_equal(
    Ok([
      [
        StringValue(fluid_ids.stable_id_to_string(stable)),
      ],
    ]),
  )
}

pub fn shared_tree_codec_field_batch_rejects_negative_summary_identifier_test() {
  let receiver = fluid_ids.new(identifier_fixture.receiver_session())
  let assert Ok(#(receiver, _)) = fluid_ids.generate(receiver)
  let #(receiver, range) = fluid_ids.take_creation_range(receiver)
  let assert Some(range) = range
  let assert Ok(receiver) = fluid_ids.finalize(receiver, range)
  let assert Error(types.CorruptData(location, _)) =
    field_batch.decode_with_context(
      identifier_batch(json.int(-1)),
      None,
      field_batch.SummaryIds(receiver),
    )
  location |> expect.to_equal("fieldBatch.data[0].value")
}

pub fn shared_tree_codec_field_batch_rejects_malformed_identifier_values_test() {
  let context =
    field_batch.SummaryIds(fluid_ids.new(identifier_fixture.receiver_session()))
  [
    json.bool(True),
    json.null(),
    json.object([]),
    stream([]),
    json.float(1.5),
    json.float(9_007_199_254_740_992.0),
    json.int(0),
  ]
  |> list.each(fn(value) {
    let assert Error(types.CorruptData(location, _)) =
      field_batch.decode_with_context(identifier_batch(value), None, context)
    location |> expect.to_equal("fieldBatch.data[0].value")
  })
}

pub fn shared_tree_codec_field_batch_rejects_malformed_identifier_streams_test() {
  let context =
    field_batch.SummaryIds(fluid_ids.new(identifier_fixture.receiver_session()))
  let shape =
    json.object([
      #(
        "c",
        json.object([
          #("type", json.string("com.fluidframework.leaf.string")),
          #("value", json.int(0)),
        ]),
      ),
    ])
  [
    encoded_batch([shape], [stream([json.int(0)])]),
    encoded_batch([shape], [
      stream([json.int(0), json.string("id"), json.string("extra")]),
    ]),
  ]
  |> list.each(fn(encoded) {
    let assert Error(types.CorruptData(location, _)) =
      field_batch.decode_with_context(encoded, None, context)
    string.starts_with(location, "fieldBatch.data[0]") |> expect.to_be_true
  })
}

pub fn shared_tree_codec_field_batch_decodes_recursive_identifier_shape_test() {
  let encoded =
    encoded_batch(
      [
        json.object([
          #(
            "c",
            json.object([
              #("type", json.string("Node")),
              #("value", json.bool(False)),
              #(
                "fields",
                json.array(
                  [
                    json.array([json.string("id"), json.int(1)], fn(value) {
                      value
                    }),
                  ],
                  fn(value) { value },
                ),
              ),
            ]),
          ),
        ]),
        json.object([
          #(
            "c",
            json.object([
              #("type", json.string("com.fluidframework.leaf.string")),
              #("value", json.int(0)),
            ]),
          ),
        ]),
      ],
      [stream([json.int(0), json.string("nested")])],
    )
  field_batch.decode(encoded)
  |> expect.to_equal(
    Ok([
      [
        ObjectValue("Node", [#("id", StringValue("nested"))]),
      ],
    ]),
  )
}

pub fn shared_tree_codec_field_batch_contextual_identifier_round_trip_test() {
  let sender_session = identifier_fixture.sender_session()
  let sender = fluid_ids.new(sender_session)
  let assert Ok(#(sender, local)) = fluid_ids.generate(sender)
  let assert Ok(stable) = fluid_ids.decompress(sender, local)
  let stable = fluid_ids.stable_id_to_string(stable)
  let before = fluid_ids.serialize(sender, True)
  let value = identifier_fixture.point(stable, stable)
  let assert Ok(encoded) =
    field_batch.encode_with_context(
      [[value]],
      Some(identifier_fixture.stored()),
      field_batch.MessageIds(sender, sender_session),
    )
  fluid_ids.serialize(sender, True) |> expect.to_equal(before)
  let encoded_text = json.to_string(encoded)
  string.split(encoded_text, stable) |> list.length |> expect.to_equal(2)
  string.contains(encoded_text, "\"id\",[4,-1]") |> expect.to_be_true

  let #(_, range) = fluid_ids.take_creation_range(sender)
  let assert Some(range) = range
  let assert Ok(receiver) =
    fluid_ids.new(identifier_fixture.receiver_session())
    |> fluid_ids.finalize(range)
  field_batch.decode_with_context(
    encoded,
    Some(identifier_fixture.stored()),
    field_batch.MessageIds(receiver, sender_session),
  )
  |> expect.to_equal(Ok([[value]]))
}

pub fn shared_tree_codec_field_batch_summary_encodes_final_identifier_test() {
  let compressor = fluid_ids.new(identifier_fixture.sender_session())
  let assert Ok(#(compressor, local)) = fluid_ids.generate(compressor)
  let assert Ok(stable) = fluid_ids.decompress(compressor, local)
  let value =
    identifier_fixture.point(fluid_ids.stable_id_to_string(stable), "ordinary")
  let #(compressor, range) = fluid_ids.take_creation_range(compressor)
  let assert Some(range) = range
  let assert Ok(compressor) = fluid_ids.finalize(compressor, range)
  let before = fluid_ids.serialize(compressor, True)
  let assert Ok(encoded) =
    field_batch.encode_with_context(
      [[value]],
      Some(identifier_fixture.stored()),
      field_batch.SummaryIds(compressor),
    )
  fluid_ids.serialize(compressor, True) |> expect.to_equal(before)
  let assert Error(types.UnsupportedFeature(_, _)) =
    field_batch.decode_with_schema(encoded, Some(identifier_fixture.stored()))
  field_batch.decode_with_context(
    encoded,
    Some(identifier_fixture.stored()),
    field_batch.SummaryIds(compressor),
  )
  |> expect.to_equal(Ok([[value]]))
}

pub fn shared_tree_codec_field_batch_encodes_nested_identifier_fields_test() {
  let sender_session = identifier_fixture.sender_session()
  let sender = fluid_ids.new(sender_session)
  let assert Ok(#(sender, left_id)) = fluid_ids.generate(sender)
  let assert Ok(#(sender, right_id)) = fluid_ids.generate(sender)
  let assert Ok(left_stable) = fluid_ids.decompress(sender, left_id)
  let assert Ok(right_stable) = fluid_ids.decompress(sender, right_id)
  let value =
    ObjectValue("Pair", [
      #(
        "left",
        identifier_fixture.point(
          fluid_ids.stable_id_to_string(left_stable),
          "left",
        ),
      ),
      #(
        "right",
        identifier_fixture.point(
          fluid_ids.stable_id_to_string(right_stable),
          "right",
        ),
      ),
    ])
  let assert Ok(encoded) =
    field_batch.encode_with_context(
      [[value]],
      Some(identifier_fixture.pair_stored()),
      field_batch.MessageIds(sender, sender_session),
    )
  let #(_, range) = fluid_ids.take_creation_range(sender)
  let assert Some(range) = range
  let assert Ok(receiver) =
    fluid_ids.new(identifier_fixture.receiver_session())
    |> fluid_ids.finalize(range)
  field_batch.decode_with_context(
    encoded,
    Some(identifier_fixture.pair_stored()),
    field_batch.MessageIds(receiver, sender_session),
  )
  |> expect.to_equal(Ok([[value]]))
}

pub fn shared_tree_codec_field_batch_summary_uses_stable_unfinalized_identifier_test() {
  let compressor = fluid_ids.new(identifier_fixture.sender_session())
  let assert Ok(#(compressor, local)) = fluid_ids.generate(compressor)
  let assert Ok(stable) = fluid_ids.decompress(compressor, local)
  let value =
    identifier_fixture.point(fluid_ids.stable_id_to_string(stable), "ordinary")
  let before = fluid_ids.serialize(compressor, True)
  let assert Ok(encoded) =
    field_batch.encode_with_context(
      [[value]],
      Some(identifier_fixture.stored()),
      field_batch.SummaryIds(compressor),
    )
  fluid_ids.serialize(compressor, True) |> expect.to_equal(before)
  field_batch.decode(encoded) |> expect.to_equal(Ok([[value]]))
}

pub fn shared_tree_codec_field_batch_uses_constant_shape_for_null_test() {
  let assert Ok(encoded) =
    field_batch.encode([[StringValue("native"), NullValue]])
  encoded
  |> expect.to_equal(
    json.object([
      #("version", json.int(2)),
      #("identifiers", json.array([], fn(value) { value })),
      #(
        "shapes",
        json.array(
          [
            json.object([
              #("c", json.object([#("extraFields", json.int(1))])),
            ]),
            json.object([#("a", json.int(2))]),
            json.object([#("d", json.int(0))]),
            json.object([
              #(
                "c",
                json.object([
                  #("type", json.string("com.fluidframework.leaf.null")),
                  #("value", json.array([json.null()], fn(value) { value })),
                ]),
              ),
            ]),
          ],
          fn(value) { value },
        ),
      ),
      #(
        "data",
        json.array(
          [
            stream([
              json.int(1),
              stream([
                json.int(0),
                json.string("com.fluidframework.leaf.string"),
                json.bool(True),
                json.string("native"),
                stream([]),
                json.int(3),
              ]),
            ]),
          ],
          fn(value) { value },
        ),
      ),
    ]),
  )
}

pub fn shared_tree_codec_field_batch_rejects_unknown_version_test() {
  let encoded =
    json.object([
      #("version", json.int(99)),
      #("identifiers", json.array([], fn(value) { value })),
      #("shapes", json.array([], fn(value) { value })),
      #("data", json.array([], fn(value) { value })),
    ])
  let assert Error(types.UnsupportedFormat(_, _)) = field_batch.decode(encoded)
  Nil
}

pub fn shared_tree_codec_field_batch_decodes_shape_grammar_test() {
  let leaf =
    json.object([
      #(
        "c",
        json.object([
          #("type", json.string("com.fluidframework.leaf.string")),
          #("value", json.bool(True)),
        ]),
      ),
    ])
  let encoded =
    encoded_batch(
      [
        leaf,
        json.object([#("a", json.int(0))]),
        json.object([
          #(
            "b",
            json.object([#("length", json.int(2)), #("shape", json.int(0))]),
          ),
        ]),
        json.object([#("d", json.int(0))]),
      ],
      [
        stream([json.int(1), stream([json.string("a"), json.string("b")])]),
        stream([json.int(2), json.string("c"), json.string("d")]),
        stream([json.int(3), json.int(0), json.string("e")]),
      ],
    )
  field_batch.decode(encoded)
  |> expect.to_equal(
    Ok([
      [StringValue("a"), StringValue("b")],
      [StringValue("c"), StringValue("d")],
      [StringValue("e")],
    ]),
  )
}

pub fn shared_tree_codec_field_batch_decodes_inline_object_and_identifiers_test() {
  let encoded =
    json.object([
      #("version", json.int(2)),
      #(
        "identifiers",
        json.array(
          ["Root", "child", "com.fluidframework.leaf.number"],
          json.string,
        ),
      ),
      #(
        "shapes",
        json.array(
          [
            json.object([
              #(
                "c",
                json.object([
                  #("type", json.int(2)),
                  #("value", json.bool(True)),
                ]),
              ),
            ]),
            json.object([#("a", json.int(0))]),
            json.object([
              #(
                "c",
                json.object([
                  #("type", json.int(0)),
                  #("value", json.bool(False)),
                  #(
                    "fields",
                    json.array(
                      [
                        json.array([json.int(1), json.int(1)], fn(value) {
                          value
                        }),
                      ],
                      fn(value) { value },
                    ),
                  ),
                ]),
              ),
            ]),
          ],
          fn(value) { value },
        ),
      ),
      #(
        "data",
        json.array(
          [stream([json.int(2), stream([json.float(4.5)])])],
          fn(value) { value },
        ),
      ),
    ])
  field_batch.decode(encoded)
  |> expect.to_equal(
    Ok([
      [ObjectValue("Root", [#("child", NumberValue(4.5))])],
    ]),
  )
}

pub fn shared_tree_codec_field_batch_decodes_upstream_compressed_test() {
  let assert Ok(fixture) = fixtures.load("tree-codecs")
  let fixtures.Case(input:, ..) = fixture
  let item_decoder = {
    use id <- decode.field("id", decode.string)
    use encoded <- decode.field("encoded", decode.dynamic)
    decode.success(#(id, wire.dynamic_to_json(encoded)))
  }
  let assert Ok(batches) =
    json.parse(
      json.to_string(input),
      decode.at(["fieldBatches"], decode.list(item_decoder)),
    )
  let assert Ok(#(_, encoded)) =
    list.find(batches, fn(batch) { batch.0 == "initial-forest-compressed" })
  field_batch.decode(encoded)
  |> expect.to_equal(
    Ok([
      [
        ObjectValue("org.watershed.shared-tree.m1.Root", [
          #("title", StringValue("")),
          #("enabled", BooleanValue(False)),
          #("rating", NumberValue(0.0)),
          #("marker", NullValue),
          #(
            "point",
            ObjectValue("org.watershed.shared-tree.m1.Point", [
              #("x", NumberValue(0.0)),
              #("y", NumberValue(0.0)),
            ]),
          ),
        ]),
      ],
    ]),
  )
}

pub fn shared_tree_codec_field_batch_round_trips_values_and_fields_test() {
  let values = [
    [
      StringValue(""),
      NumberValue(-1.7976931348623157e308),
      BooleanValue(False),
      NullValue,
      ObjectValue("Node", [
        #("水", StringValue("🌊")),
        #("child", ObjectValue("Empty", [])),
      ]),
    ],
    [],
  ]
  let assert Ok(encoded) = field_batch.encode(values)
  field_batch.decode(encoded) |> expect.to_equal(Ok(values))
}

pub fn shared_tree_codec_field_batch_round_trips_map_values_with_schema_test() {
  let values = [
    [
      MapValue(map_type, [
        #("", StringValue("empty-key")),
        #("__proto__", StringValue("safe")),
        #("nested", MapValue(map_type, [#("水", NumberValue(42.0))])),
      ]),
    ],
  ]
  let assert Ok(encoded) = field_batch.encode(values)
  field_batch.decode_with_schema(encoded, Some(map_schema()))
  |> expect.to_equal(Ok(values))
}

pub fn shared_tree_codec_field_batch_round_trips_array_values_with_schema_test() {
  let values = [
    [
      ArrayValue("org.watershed.shared-tree.m3.Items", [
        StringValue("B"),
        StringValue("A"),
        StringValue("B"),
      ]),
    ],
  ]
  let assert Ok(encoded) = field_batch.encode(values)
  field_batch.decode_with_schema(encoded, Some(array_schema()))
  |> expect.to_equal(Ok(values))
}

pub fn shared_tree_codec_field_batch_decodes_source_array_content_test() {
  let assert Ok(fixture) = fixtures.load("array-schema-content")
  let assert Ok(input) = fixture_codec.parse(fixture.input)
  let assert Ok(scenarios) =
    fixture_codec.field(input, "scenarios", fixture_codec.items)
  let assert Ok(summary) = scenarios |> list.drop(9) |> list.first
  let assert Ok(raw) =
    fixture_codec.field(summary, "forestBytes", fixture_codec.text)
  let assert Ok(encoded) =
    json.parse(raw, {
      use fields <- decode.field("fields", decode.dynamic)
      decode.success(fields)
    })
  let root =
    ObjectValue(root_type, [
      #(
        "left",
        ArrayValue(array_type, [
          StringValue("A"),
          ObjectValue(point_type, [
            #("label", StringValue("same")),
            #("x", NumberValue(1.0)),
          ]),
          ObjectValue(point_type, [
            #("label", StringValue("same")),
            #("x", NumberValue(1.0)),
          ]),
          ArrayValue(array_type, [
            StringValue("nested"),
            MapValue(array_map_type, [
              #("", StringValue("empty-key")),
              #("0", StringValue("numeric-key")),
            ]),
          ]),
        ]),
      ),
      #("right", ArrayValue(array_type, [StringValue("R")])),
      #(
        "byKey",
        MapValue(array_map_type, [
          #("", ArrayValue(array_type, [StringValue("empty")])),
          #(
            "0",
            ArrayValue(array_type, [
              StringValue("zero"),
              ArrayValue(array_type, [StringValue("deep")]),
            ]),
          ),
          #("01", StringValue("leading-zero")),
        ]),
      ),
      #(
        "narrow",
        ArrayValue(points_type, [
          ObjectValue(point_type, [
            #("label", StringValue("narrow")),
            #("x", NumberValue(9.0)),
          ]),
        ]),
      ),
    ])
  field_batch.decode_with_schema(
    wire.dynamic_to_json(encoded),
    Some({
      let assert Ok(fixture) = fixtures.load("array-schema-content")
      let assert Ok(raw) =
        json.parse(
          json.to_string(fixture.input),
          decode.at(["schemas", "objectArrays"], decode.string),
        )
      let assert Ok(stored) = schema.stored_from_string(raw)
      stored
    }),
  )
  |> expect.to_equal(Ok([[root]]))
}

pub fn shared_tree_codec_field_batch_decodes_omitted_empty_array_field_test() {
  let encoded =
    encoded_batch(
      [
        json.object([
          #(
            "c",
            json.object([
              #("type", json.string(array_type)),
              #("value", json.bool(False)),
            ]),
          ),
        ]),
      ],
      [stream([json.int(0)])],
    )
  field_batch.decode_with_schema(encoded, Some(array_schema()))
  |> expect.to_equal(Ok([[ArrayValue(array_type, [])]]))
}

pub fn shared_tree_codec_field_batch_accepts_empty_leaf_fields_test() {
  let encoded =
    json.object([
      #("version", json.int(2)),
      #("identifiers", json.array([], fn(value) { value })),
      #(
        "shapes",
        json.array(
          [
            json.object([
              #(
                "c",
                json.object([
                  #("type", json.string("com.fluidframework.leaf.string")),
                  #("value", json.bool(True)),
                  #(
                    "fields",
                    json.array(
                      [
                        json.array(
                          [json.string("empty"), json.int(1)],
                          fn(value) { value },
                        ),
                      ],
                      fn(value) { value },
                    ),
                  ),
                ]),
              ),
            ]),
            json.object([#("a", json.int(2))]),
            json.object([
              #(
                "c",
                json.object([
                  #("type", json.string("com.fluidframework.leaf.string")),
                  #("value", json.bool(True)),
                ]),
              ),
            ]),
          ],
          fn(value) { value },
        ),
      ),
      #(
        "data",
        json.array(
          [
            stream([
              json.int(0),
              json.string("value"),
              stream([]),
            ]),
          ],
          fn(value) { value },
        ),
      ),
    ])
  field_batch.decode(encoded)
  |> expect.to_equal(Ok([[StringValue("value")]]))
}

pub fn shared_tree_codec_field_batch_accepts_finite_recursive_shape_test() {
  let encoded =
    encoded_batch(
      [
        json.object([
          #(
            "c",
            json.object([
              #("type", json.string("Node")),
              #("value", json.bool(False)),
              #(
                "fields",
                json.array(
                  [
                    json.array([json.string("child"), json.int(1)], fn(value) {
                      value
                    }),
                  ],
                  fn(value) { value },
                ),
              ),
            ]),
          ),
        ]),
        json.object([#("a", json.int(0))]),
      ],
      [stream([json.int(0), stream([stream([])])])],
    )
  field_batch.decode(encoded)
  |> expect.to_equal(
    Ok([
      [ObjectValue("Node", [#("child", ObjectValue("Node", []))])],
    ]),
  )
}

pub fn shared_tree_codec_field_batch_rejects_malformed_streams_test() {
  let node =
    json.object([
      #(
        "c",
        json.object([
          #("type", json.string("com.fluidframework.leaf.string")),
          #("value", json.bool(True)),
        ]),
      ),
    ])
  let cases = [
    encoded_batch([node], [stream([json.int(0)])]),
    encoded_batch([node], [
      stream([json.int(0), json.string("ok"), json.string("trailing")]),
    ]),
    encoded_batch(
      [
        json.object([
          #(
            "b",
            json.object([#("length", json.int(1)), #("shape", json.int(0))]),
          ),
        ]),
      ],
      [stream([json.int(0)])],
    ),
    encoded_batch([json.object([#("a", json.int(0)), #("d", json.int(0))])], [
      stream([json.int(0), stream([])]),
    ]),
    encoded_batch(
      [json.object([#("a", json.int(0)), #("extra", json.bool(True))])],
      [stream([json.int(0), stream([])])],
    ),
    encoded_batch([json.object([#("a", json.int(0))])], [
      stream([json.int(0), json.int(-1)]),
    ]),
    encoded_batch([json.object([#("d", json.int(0))])], [
      stream([json.int(0), json.float(9_007_199_254_740_992.0)]),
    ]),
    encoded_batch(
      [
        json.object([
          #("c", json.object([#("extraFields", json.int(1))])),
        ]),
        json.object([#("a", json.int(0))]),
      ],
      [
        stream([
          json.int(0),
          json.string("Node"),
          json.bool(False),
          stream([
            json.string("same"),
            stream([]),
            json.string("same"),
            stream([]),
          ]),
        ]),
      ],
    ),
  ]
  cases
  |> list.each(fn(encoded) {
    let assert Error(types.CorruptData(location, detail)) =
      field_batch.decode(encoded)
    string.is_empty(location) |> expect.to_be_false
    string.is_empty(detail) |> expect.to_be_false
  })
}

pub fn shared_tree_codec_field_batch_refuses_excluded_content_test() {
  let cases = [
    encoded_batch([json.object([#("e", json.int(0))])], [
      stream([json.int(0), json.int(1)]),
    ]),
    encoded_batch(
      [
        json.object([
          #(
            "c",
            json.object([
              #("type", json.string("com.fluidframework.leaf.handle")),
              #("value", json.bool(True)),
            ]),
          ),
        ]),
      ],
      [stream([json.int(0), json.string("/handle")])],
    ),
    encoded_batch(
      [
        json.object([
          #(
            "c",
            json.object([
              #("type", json.string("com.fluidframework.node.identifier")),
              #("value", json.int(0)),
            ]),
          ),
        ]),
      ],
      [stream([json.int(0), json.string("id")])],
    ),
  ]
  cases
  |> list.each(fn(encoded) {
    let assert Error(types.UnsupportedFeature(_, _)) =
      field_batch.decode(encoded)
  })
}
