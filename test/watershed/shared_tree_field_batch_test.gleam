import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import startest/expect
import watershed/tree/codec/field_batch
import watershed/tree/fixtures
import watershed/tree/schema
import watershed/tree/types.{
  BooleanValue, MapValue, NullValue, NumberValue, ObjectValue, StringValue,
}
import watershed/wire

const map_type = "org.watershed.shared-tree.m2.DynamicMap"

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

pub fn shared_tree_codec_field_batch_uncompressed_string_test() {
  let fields = [[StringValue("native")]]
  let assert Ok(encoded) = field_batch.encode(fields)
  let assert Ok(decoded) = field_batch.decode(encoded)
  decoded |> expect.to_equal(fields)
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
