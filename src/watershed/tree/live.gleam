//// Typed snapshots and checkout-local references for native SharedTree.

import gleam/dict.{type Dict}
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/tree/live_types as protocol
import watershed/tree/schema
import watershed/tree/schema_builder as builder
import watershed/tree/types

@internal
pub type Backend {
  Backend(
    request: fn(protocol.Request) ->
      Result(protocol.Response, protocol.LiveError),
    subscribe: fn(fn() -> Nil) -> Result(fn() -> Nil, protocol.LiveError),
  )
}

type Encoding {
  Snapshot
  NewContent
}

type Codec(a) {
  Codec(
    encode: fn(Encoding, a) -> Result(Option(types.TreeValue), types.TreeError),
    decode: fn(Option(types.TreeValue)) -> Result(a, types.TreeError),
  )
}

pub opaque type View(a) {
  View(
    token: protocol.ViewToken,
    compiled: builder.Compiled(a),
    backend: Backend,
  )
}

pub opaque type Ref(a) {
  Ref(
    anchor: protocol.AnchorToken,
    identifier: String,
    codec: Codec(a),
    backend: Backend,
  )
}

pub opaque type Subscription {
  Subscription(cancel: fn() -> Nil)
}

@internal
pub fn bind(
  compiled: builder.Compiled(a),
  backend: Backend,
) -> Result(View(a), protocol.LiveError) {
  use response <- result.try(
    backend.request(protocol.Bind(builder.view(compiled))),
  )
  case response {
    protocol.Bound(token) -> Ok(from_bound(compiled, backend, token))
    _ -> unexpected()
  }
}

@internal
pub fn from_bound(
  compiled: builder.Compiled(a),
  backend: Backend,
  token: protocol.ViewToken,
) -> View(a) {
  View(token, compiled, backend)
}

fn unexpected() -> Result(a, protocol.LiveError) {
  Error(protocol.RuntimeFailure("Unexpected typed tree response"))
}

fn codec(compiled: builder.Compiled(a)) -> Codec(a) {
  Codec(
    fn(mode, value) {
      case mode {
        Snapshot -> builder.encode(compiled, value)
        NewContent -> builder.encode_new(compiled, value)
      }
    },
    builder.decode(compiled, _),
  )
}

fn absent() -> types.TreeError {
  types.InvalidEdit([], "Required typed value is absent")
}

fn unwrap(optional: Codec(Option(a))) -> Codec(a) {
  Codec(fn(mode, value) { optional.encode(mode, Some(value)) }, fn(snapshot) {
    use value <- result.try(optional.decode(snapshot))
    option.to_result(value, absent())
  })
}

fn snapshot(
  backend: Backend,
  request: protocol.Request,
  codec: Codec(a),
) -> Result(a, protocol.LiveError) {
  use response <- result.try(backend.request(request))
  case response {
    protocol.Snapshot(value) ->
      codec.decode(value) |> result.map_error(protocol.InvalidValue)
    _ -> unexpected()
  }
}

fn done(
  backend: Backend,
  request: protocol.Request,
) -> Result(Nil, protocol.LiveError) {
  use response <- result.try(backend.request(request))
  case response {
    protocol.Done -> Ok(Nil)
    _ -> unexpected()
  }
}

fn evidence(
  backend: Backend,
  codec: Codec(a),
  node: protocol.NodeEvidence,
  view: protocol.ViewToken,
) -> Result(Ref(a), protocol.LiveError) {
  use _ <- result.try(case protocol.anchor_view(node.anchor) == view {
    True -> Ok(Nil)
    False -> Error(protocol.ForeignOrigin)
  })
  use _ <- result.try(case node.snapshot {
    types.ObjectValue(_, _) | types.ArrayValue(_, _) | types.MapValue(_, _) ->
      Ok(Nil)
    _ -> Error(protocol.WrongKind("composite", node.identifier))
  })
  use _ <- result.try(
    case schema.value_identifier(node.snapshot) == node.identifier {
      True -> Ok(Nil)
      False ->
        Error(protocol.RuntimeFailure(
          "Node evidence has an incorrect identifier",
        ))
    },
  )
  use _ <- result.try(
    codec.decode(Some(node.snapshot)) |> result.map_error(protocol.InvalidValue),
  )
  Ok(Ref(node.anchor, node.identifier, codec, backend))
}

fn acquire(
  backend: Backend,
  request: protocol.Request,
  codec: Codec(a),
  view: protocol.ViewToken,
) -> Result(Option(Ref(a)), protocol.LiveError) {
  use response <- result.try(backend.request(request))
  case response {
    protocol.Acquired(None) -> Ok(None)
    protocol.Acquired(Some(node)) ->
      evidence(backend, codec, node, view) |> result.map(Some)
    _ -> unexpected()
  }
}

fn require(reference: Option(Ref(a))) -> Result(Ref(a), protocol.LiveError) {
  option.to_result(reference, protocol.InvalidValue(absent()))
}

pub fn read_root(view: View(a)) -> Result(a, protocol.LiveError) {
  snapshot(view.backend, protocol.RootRead(view.token), codec(view.compiled))
}

pub fn replace_root(
  view: View(a),
  value: a,
) -> Result(Nil, protocol.LiveError) {
  replace(view, value, Snapshot)
}

pub fn replace_root_new(
  view: View(a),
  value: a,
) -> Result(Nil, protocol.LiveError) {
  replace(view, value, NewContent)
}

fn replace(
  view: View(a),
  value: a,
  mode: Encoding,
) -> Result(Nil, protocol.LiveError) {
  use encoded <- result.try(
    codec(view.compiled).encode(mode, value)
    |> result.map_error(protocol.InvalidValue),
  )
  done(view.backend, protocol.RootReplace(view.token, encoded))
}

pub fn required_root(view: View(a)) -> Result(Ref(a), protocol.LiveError) {
  use _ <- result.try(cardinality(
    builder.root_cardinality(view.compiled),
    schema.Required,
  ))
  use reference <- result.try(acquire(
    view.backend,
    protocol.RootAcquire(view.token, schema.Required),
    codec(view.compiled),
    view.token,
  ))
  require(reference)
}

pub fn optional_root(
  view: View(Option(a)),
) -> Result(Option(Ref(a)), protocol.LiveError) {
  use _ <- result.try(cardinality(
    builder.root_cardinality(view.compiled),
    schema.Optional,
  ))
  acquire(
    view.backend,
    protocol.RootAcquire(view.token, schema.Optional),
    unwrap(codec(view.compiled)),
    view.token,
  )
}

pub fn read(reference: Ref(a)) -> Result(a, protocol.LiveError) {
  snapshot(reference.backend, protocol.Read(reference.anchor), reference.codec)
}

pub fn status(
  reference: Ref(a),
) -> Result(protocol.ReferenceStatus, protocol.LiveError) {
  use response <- result.try(
    reference.backend.request(protocol.Status(reference.anchor)),
  )
  case response {
    protocol.ReferenceState(status) -> Ok(status)
    _ -> unexpected()
  }
}

pub fn dispose(view: View(a)) -> Result(Nil, protocol.LiveError) {
  done(view.backend, protocol.Close(view.token))
}

fn property_codec(
  property: builder.Property(record, a),
) -> Result(Codec(a), protocol.LiveError) {
  builder.property_root(property)
  |> builder.compile
  |> result.map(codec)
  |> result.map_error(protocol.InvalidSchema)
}

fn proof(property: builder.Property(record, a)) -> protocol.FieldProof {
  let #(key, field) = builder.property_definition(property)
  protocol.FieldProof(key, field)
}

fn cardinality(
  actual: schema.Cardinality,
  expected: schema.Cardinality,
) -> Result(Nil, protocol.LiveError) {
  case actual == expected {
    True -> Ok(Nil)
    False -> Error(protocol.WrongCardinality)
  }
}

pub fn get(
  reference: Ref(record),
  property: builder.Property(record, a),
) -> Result(a, protocol.LiveError) {
  use codec <- result.try(property_codec(property))
  snapshot(
    reference.backend,
    protocol.PropertyRead(reference.anchor, proof(property)),
    codec,
  )
}

pub fn set(
  reference: Ref(record),
  property: builder.Property(record, a),
  value: a,
) -> Result(Nil, protocol.LiveError) {
  set_property(reference, property, value, Snapshot)
}

pub fn set_new(
  reference: Ref(record),
  property: builder.Property(record, a),
  value: a,
) -> Result(Nil, protocol.LiveError) {
  set_property(reference, property, value, NewContent)
}

fn set_property(
  reference: Ref(record),
  property: builder.Property(record, a),
  value: a,
  mode: Encoding,
) -> Result(Nil, protocol.LiveError) {
  use codec <- result.try(property_codec(property))
  use value <- result.try(
    codec.encode(mode, value) |> result.map_error(protocol.InvalidValue),
  )
  done(
    reference.backend,
    protocol.PropertySet(reference.anchor, proof(property), value),
  )
}

pub fn child(
  reference: Ref(record),
  property: builder.Property(record, a),
) -> Result(Ref(a), protocol.LiveError) {
  use _ <- result.try(cardinality(
    proof(property).definition.cardinality,
    schema.Required,
  ))
  use codec <- result.try(property_codec(property))
  use child <- result.try(acquire(
    reference.backend,
    protocol.ChildAcquire(reference.anchor, proof(property)),
    codec,
    protocol.anchor_view(reference.anchor),
  ))
  require(child)
}

pub fn optional_child(
  reference: Ref(record),
  property: builder.Property(record, Option(a)),
) -> Result(Option(Ref(a)), protocol.LiveError) {
  use _ <- result.try(cardinality(
    proof(property).definition.cardinality,
    schema.Optional,
  ))
  use codec <- result.try(property_codec(property))
  acquire(
    reference.backend,
    protocol.ChildAcquire(reference.anchor, proof(property)),
    unwrap(codec),
    protocol.anchor_view(reference.anchor),
  )
}

pub fn narrow(
  reference: Ref(sum),
  node: builder.Node(a),
) -> Result(Option(Ref(a)), protocol.LiveError) {
  use compiled <- result.try(
    builder.compile(builder.root(node))
    |> result.map_error(protocol.InvalidSchema),
  )
  acquire(
    reference.backend,
    protocol.Narrow(reference.anchor, builder.allowed_types(node)),
    codec(compiled),
    protocol.anchor_view(reference.anchor),
  )
}

fn array_codec(reference: Ref(List(a))) -> Codec(a) {
  Codec(
    fn(mode, value) {
      use encoded <- result.try(reference.codec.encode(mode, [value]))
      case encoded {
        Some(types.ArrayValue(identifier, [value]))
          if identifier == reference.identifier
        -> Ok(Some(value))
        _ ->
          Error(types.CorruptData("typed tree", "Invalid array codec result"))
      }
    },
    fn(snapshot) {
      use value <- result.try(option.to_result(snapshot, absent()))
      use values <- result.try(
        reference.codec.decode(
          Some(types.ArrayValue(reference.identifier, [value])),
        ),
      )
      case values {
        [value] -> Ok(value)
        _ ->
          Error(types.CorruptData("typed tree", "Invalid array codec result"))
      }
    },
  )
}

fn optional_snapshot(
  backend: Backend,
  request: protocol.Request,
  codec: Codec(a),
) -> Result(Option(a), protocol.LiveError) {
  use response <- result.try(backend.request(request))
  case response {
    protocol.Snapshot(None) -> Ok(None)
    protocol.Snapshot(Some(value)) ->
      codec.decode(Some(value))
      |> result.map(Some)
      |> result.map_error(protocol.InvalidValue)
    _ -> unexpected()
  }
}

pub fn array_get(
  reference: Ref(List(a)),
  index: Int,
) -> Result(Option(a), protocol.LiveError) {
  optional_snapshot(
    reference.backend,
    protocol.ArrayRead(reference.anchor, index),
    array_codec(reference),
  )
}

pub fn array_node(
  reference: Ref(List(a)),
  index: Int,
) -> Result(Option(Ref(a)), protocol.LiveError) {
  acquire(
    reference.backend,
    protocol.ArrayAcquire(reference.anchor, index),
    array_codec(reference),
    protocol.anchor_view(reference.anchor),
  )
}

pub fn array_insert(
  reference: Ref(List(a)),
  index: Int,
  values: List(a),
) -> Result(Nil, protocol.LiveError) {
  insert(reference, index, values, Snapshot)
}

pub fn array_insert_new(
  reference: Ref(List(a)),
  index: Int,
  values: List(a),
) -> Result(Nil, protocol.LiveError) {
  insert(reference, index, values, NewContent)
}

fn insert(
  reference: Ref(List(a)),
  index: Int,
  values: List(a),
  mode: Encoding,
) -> Result(Nil, protocol.LiveError) {
  use encoded <- result.try(
    reference.codec.encode(mode, values)
    |> result.map_error(protocol.InvalidValue),
  )
  case encoded {
    Some(types.ArrayValue(identifier, values))
      if identifier == reference.identifier
    ->
      done(
        reference.backend,
        protocol.ArrayInsert(reference.anchor, index, values),
      )
    _ -> Error(protocol.WrongKind("array", reference.identifier))
  }
}

pub fn array_remove(
  reference: Ref(List(a)),
  start: Int,
  end: Int,
) -> Result(Nil, protocol.LiveError) {
  done(reference.backend, protocol.ArrayRemove(reference.anchor, start, end))
}

pub fn array_move(
  source: Ref(List(a)),
  start: Int,
  end: Int,
  destination: Ref(List(a)),
  gap: Int,
) -> Result(Nil, protocol.LiveError) {
  done(
    source.backend,
    protocol.ArrayMove(source.anchor, start, end, destination.anchor, gap),
  )
}

fn map_codec(reference: Ref(Dict(String, a))) -> Codec(a) {
  Codec(
    fn(mode, value) {
      use encoded <- result.try(reference.codec.encode(
        mode,
        dict.from_list([#("", value)]),
      ))
      case encoded {
        Some(types.MapValue(identifier, [#("", value)]))
          if identifier == reference.identifier
        -> Ok(Some(value))
        _ -> Error(types.CorruptData("typed tree", "Invalid map codec result"))
      }
    },
    fn(snapshot) {
      use value <- result.try(option.to_result(snapshot, absent()))
      use values <- result.try(
        reference.codec.decode(
          Some(types.MapValue(reference.identifier, [#("", value)])),
        ),
      )
      dict.get(values, "")
      |> result.map_error(fn(_) {
        types.CorruptData("typed tree", "Invalid map codec result")
      })
    },
  )
}

pub fn map_get(
  reference: Ref(Dict(String, a)),
  key: String,
) -> Result(Option(a), protocol.LiveError) {
  optional_snapshot(
    reference.backend,
    protocol.MapRead(reference.anchor, key),
    map_codec(reference),
  )
}

pub fn map_node(
  reference: Ref(Dict(String, a)),
  key: String,
) -> Result(Option(Ref(a)), protocol.LiveError) {
  acquire(
    reference.backend,
    protocol.MapAcquire(reference.anchor, key),
    map_codec(reference),
    protocol.anchor_view(reference.anchor),
  )
}

pub fn map_set(
  reference: Ref(Dict(String, a)),
  key: String,
  value: a,
) -> Result(Nil, protocol.LiveError) {
  set_map(reference, key, value, Snapshot)
}

pub fn map_set_new(
  reference: Ref(Dict(String, a)),
  key: String,
  value: a,
) -> Result(Nil, protocol.LiveError) {
  set_map(reference, key, value, NewContent)
}

fn set_map(
  reference: Ref(Dict(String, a)),
  key: String,
  value: a,
  mode: Encoding,
) -> Result(Nil, protocol.LiveError) {
  use encoded <- result.try(
    map_codec(reference).encode(mode, value)
    |> result.map_error(protocol.InvalidValue),
  )
  case encoded {
    Some(value) ->
      done(reference.backend, protocol.MapSet(reference.anchor, key, value))
    None -> Error(protocol.InvalidValue(absent()))
  }
}

pub fn map_delete(
  reference: Ref(Dict(String, a)),
  key: String,
) -> Result(Nil, protocol.LiveError) {
  done(reference.backend, protocol.MapDelete(reference.anchor, key))
}

pub fn observe(
  view: View(a),
  handler: fn(Result(a, protocol.LiveError)) -> Nil,
) -> Result(Subscription, protocol.LiveError) {
  use _ <- result.try(read_root(view))
  use cancel <- result.try(
    view.backend.subscribe(fn() { handler(read_root(view)) }),
  )
  Ok(Subscription(cancel))
}

pub fn observe_node(
  reference: Ref(a),
  handler: fn(Result(a, protocol.LiveError)) -> Nil,
) -> Result(Subscription, protocol.LiveError) {
  use _ <- result.try(read(reference))
  use cancel <- result.try(
    reference.backend.subscribe(fn() { handler(read(reference)) }),
  )
  Ok(Subscription(cancel))
}

pub fn unsubscribe(subscription: Subscription) -> Nil {
  subscription.cancel()
}
