import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import watershed/canonical_json
import watershed/fluid_ids.{type StableId}
import watershed/json_ot.{type JsonValue, VArray, VBool, VNull, VObject, VString}
import watershed/tree/change
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/optional_field
import watershed/tree/types

pub fn parse(value: Json) -> Result(JsonValue, String) {
  json.parse(json.to_string(value), json_ot.decoder())
  |> result.map_error(string.inspect)
}

pub fn exact(value: JsonValue, keys: List(String)) -> Result(Nil, String) {
  case value {
    VObject(fields) -> {
      let actual = list.map(fields, fn(pair) { pair.0 })
      case
        list.sort(actual, canonical_json.compare)
        == list.sort(keys, canonical_json.compare)
      {
        True -> Ok(Nil)
        False -> Error("unexpected object keys: " <> string.inspect(actual))
      }
    }
    _ -> Error("expected an object")
  }
}

pub fn get(value: JsonValue, key: String) -> Result(JsonValue, String) {
  case value {
    VObject(fields) ->
      list.key_find(fields, key)
      |> result.map_error(fn(_) { "missing field " <> key })
    _ -> Error("expected an object for " <> key)
  }
}

pub fn text(value: JsonValue) -> Result(String, String) {
  case value {
    VString(value) -> Ok(value)
    _ -> Error("expected a string")
  }
}

pub fn integer(value: JsonValue) -> Result(Int, String) {
  case value {
    json_ot.VNumber(json_ot.NInt(value)) -> Ok(value)
    _ -> Error("expected an integer")
  }
}

pub fn boolean(value: JsonValue) -> Result(Bool, String) {
  case value {
    VBool(value) -> Ok(value)
    _ -> Error("expected a boolean")
  }
}

pub fn items(value: JsonValue) -> Result(List(JsonValue), String) {
  case value {
    VArray(values) -> Ok(values)
    _ -> Error("expected an array")
  }
}

pub fn pair(value: JsonValue) -> Result(#(JsonValue, JsonValue), String) {
  case value {
    VArray([first, second]) -> Ok(#(first, second))
    _ -> Error("expected a two-element entry")
  }
}

pub fn field(
  value: JsonValue,
  key: String,
  decode: fn(JsonValue) -> Result(a, String),
) -> Result(a, String) {
  use entry <- result.try(get(value, key))
  decode(entry)
}

pub fn many(
  value: JsonValue,
  decode: fn(JsonValue) -> Result(a, String),
) -> Result(List(a), String) {
  use values <- result.try(items(value))
  list.try_map(values, decode)
}

pub fn optional(
  value: JsonValue,
  decode: fn(JsonValue) -> Result(a, String),
) -> Result(Option(a), String) {
  case value {
    VNull -> Ok(None)
    value -> decode(value) |> result.map(Some)
  }
}

pub fn revision(value: JsonValue) -> Result(StableId, String) {
  use raw <- result.try(text(value))
  fluid_ids.stable_id(raw) |> result.map_error(string.inspect)
}

pub fn atom(value: JsonValue) -> Result(types.AtomId, String) {
  use _ <- result.try(exact(value, ["revision", "localId"]))
  use revision <- result.try(
    field(value, "revision", fn(value) { optional(value, revision) }),
  )
  use local_id <- result.try(field(value, "localId", integer))
  Ok(types.AtomId(revision:, local_id:))
}

pub fn tree(value: JsonValue) -> Result(types.TreeValue, String) {
  json.parse(
    json.to_string(json_ot.to_json(value)),
    fixtures.tree_value_decoder(),
  )
  |> result.map_error(string.inspect)
}

pub fn build(value: JsonValue) -> Result(forest.Build, String) {
  use _ <- result.try(exact(value, ["id", "trees"]))
  use id <- result.try(field(value, "id", atom))
  use trees <- result.try(
    field(value, "trees", fn(value) { many(value, tree) }),
  )
  Ok(forest.Build(id, trees))
}

fn destroy(value: JsonValue) -> Result(forest.Destroy, String) {
  use _ <- result.try(exact(value, ["id", "count"]))
  use id <- result.try(field(value, "id", atom))
  use count <- result.try(field(value, "count", integer))
  Ok(forest.Destroy(id, count))
}

pub fn revision_info(value: JsonValue) -> Result(change.RevisionInfo, String) {
  use _ <- result.try(exact(value, ["revision", "rollbackOf"]))
  use revision_id <- result.try(field(value, "revision", revision))
  use rollback_of <- result.try(
    field(value, "rollbackOf", fn(value) { optional(value, revision) }),
  )
  Ok(change.RevisionInfo(revision_id, rollback_of))
}

pub fn state(
  value: JsonValue,
  identity_order: change.IdentityOrder,
) -> Result(change.Changeset, String) {
  use _ <- result.try(
    exact(value, [
      "maxLocalId", "revisions", "fields", "nodes", "parents", "aliases",
      "builds", "destroys", "refreshers",
    ]),
  )
  use max_local_id <- result.try(field(value, "maxLocalId", integer))
  use revisions <- result.try(
    field(value, "revisions", fn(value) { many(value, revision_info) }),
  )
  use root_fields <- result.try(field(value, "fields", fields))
  use nodes <- result.try(
    field(value, "nodes", fn(value) {
      many(value, fn(entry) {
        use #(id, node) <- result.try(pair(entry))
        use id <- result.try(atom(id))
        use _ <- result.try(exact(node, ["fields"]))
        use fields <- result.try(field(node, "fields", fields))
        Ok(#(id, change.NodeChange(fields)))
      })
    }),
  )
  use parents <- result.try(
    field(value, "parents", fn(value) {
      many(value, fn(entry) {
        use #(id, parent) <- result.try(pair(entry))
        use id <- result.try(atom(id))
        use _ <- result.try(exact(parent, ["parent", "field"]))
        use parent_id <- result.try(
          field(parent, "parent", fn(value) { optional(value, atom) }),
        )
        use key <- result.try(field(parent, "field", text))
        Ok(#(id, change.ParentField(parent_id, key)))
      })
    }),
  )
  use aliases <- result.try(
    field(value, "aliases", fn(value) { many(value, atom_pair) }),
  )
  use builds <- result.try(
    field(value, "builds", fn(value) { many(value, build) }),
  )
  use destroys <- result.try(
    field(value, "destroys", fn(value) { many(value, destroy) }),
  )
  use refreshers <- result.try(
    field(value, "refreshers", fn(value) { many(value, build) }),
  )
  change.from_data(
    change.ChangeData(
      max_local_id:,
      revisions:,
      fields: root_fields,
      nodes:,
      parents:,
      aliases:,
      builds:,
      destroys:,
      refreshers:,
    ),
    identity_order,
  )
  |> native
}

fn fields(
  value: JsonValue,
) -> Result(List(#(String, change.FieldChange)), String) {
  many(value, fn(entry) {
    use #(key, value) <- result.try(pair(entry))
    use key <- result.try(text(key))
    use kind <- result.try(field(value, "kind", text))
    use decoded <- result.try(case kind {
      "Generic" -> {
        use _ <- result.try(exact(value, ["kind", "children"]))
        use children <- result.try(
          field(value, "children", fn(value) {
            many(value, fn(entry) {
              use #(index, id) <- result.try(pair(entry))
              use index <- result.try(integer(index))
              use id <- result.try(atom(id))
              Ok(#(index, id))
            })
          }),
        )
        Ok(change.GenericField(children))
      }
      "Value" | "Optional" -> {
        use _ <- result.try(
          exact(value, ["kind", "moves", "children", "replacement"]),
        )
        use moves <- result.try(
          field(value, "moves", fn(value) { many(value, atom_pair) }),
        )
        use children <- result.try(
          field(value, "children", fn(value) {
            many(value, fn(entry) {
              use #(raw_register, id) <- result.try(pair(entry))
              use register <- result.try(register(raw_register))
              use id <- result.try(atom(id))
              Ok(#(register, id))
            })
          }),
        )
        use replacement <- result.try(
          field(value, "replacement", fn(value) { optional(value, replacement) }),
        )
        let change = optional_field.FieldChange(moves, children, replacement)
        case kind {
          "Value" -> Ok(change.ValueField(change))
          _ -> Ok(change.OptionalField(change))
        }
      }
      _ -> Error("unsupported modular field kind: " <> kind)
    })
    Ok(#(key, decoded))
  })
}

fn atom_pair(
  value: JsonValue,
) -> Result(#(types.AtomId, types.AtomId), String) {
  use #(first, second) <- result.try(pair(value))
  use first <- result.try(atom(first))
  use second <- result.try(atom(second))
  Ok(#(first, second))
}

fn register(value: JsonValue) -> Result(optional_field.RegisterId, String) {
  case value {
    VString("active") -> Ok(optional_field.Active)
    _ -> atom(value) |> result.map(optional_field.Detached)
  }
}

fn replacement(value: JsonValue) -> Result(optional_field.Replacement, String) {
  use _ <- result.try(exact(value, ["wasEmpty", "source", "detach"]))
  use was_empty <- result.try(field(value, "wasEmpty", boolean))
  use source <- result.try(
    field(value, "source", fn(value) { optional(value, register) }),
  )
  use detach <- result.try(field(value, "detach", atom))
  Ok(optional_field.Replacement(was_empty, source, detach))
}

pub fn array(values: List(Json)) -> Json {
  json.array(values, fn(value) { value })
}

pub fn nullable(value: Option(a), encode: fn(a) -> Json) -> Json {
  case value {
    None -> json.null()
    Some(value) -> encode(value)
  }
}

pub fn revision_json(value: StableId) -> Json {
  json.string(fluid_ids.stable_id_to_string(value))
}

pub fn atom_json(value: types.AtomId) -> Json {
  json.object([
    #("revision", nullable(value.revision, revision_json)),
    #("localId", json.int(value.local_id)),
  ])
}

pub fn revision_info_json(value: change.RevisionInfo) -> Json {
  json.object([
    #("revision", revision_json(value.revision)),
    #("rollbackOf", nullable(value.rollback_of, revision_json)),
  ])
}

pub fn build_json(value: forest.Build) -> Json {
  json.object([
    #("id", atom_json(value.id)),
    #("trees", json.array(value.trees, fixtures.tree_value_to_json)),
  ])
}

fn destroy_json(value: forest.Destroy) -> Json {
  json.object([
    #("id", atom_json(value.id)),
    #("count", json.int(value.count)),
  ])
}

pub fn state_json(value: change.Changeset) -> Json {
  let value = change.to_data(value)
  json.object([
    #("maxLocalId", json.int(value.max_local_id)),
    #("revisions", json.array(value.revisions, revision_info_json)),
    #("fields", fields_json(value.fields)),
    #(
      "nodes",
      json.array(value.nodes, fn(entry) {
        array([
          atom_json(entry.0),
          json.object([#("fields", fields_json(entry.1.fields))]),
        ])
      }),
    ),
    #(
      "parents",
      json.array(value.parents, fn(entry) {
        array([
          atom_json(entry.0),
          json.object([
            #("parent", nullable(entry.1.parent, atom_json)),
            #("field", json.string(entry.1.field)),
          ]),
        ])
      }),
    ),
    #(
      "aliases",
      json.array(value.aliases, fn(entry) {
        array([atom_json(entry.0), atom_json(entry.1)])
      }),
    ),
    #("builds", json.array(value.builds, build_json)),
    #("destroys", json.array(value.destroys, destroy_json)),
    #("refreshers", json.array(value.refreshers, build_json)),
  ])
}

fn fields_json(values: List(#(String, change.FieldChange))) -> Json {
  json.array(values, fn(entry) {
    array([json.string(entry.0), field_json(entry.1)])
  })
}

fn field_json(value: change.FieldChange) -> Json {
  case value {
    change.GenericField(children) ->
      json.object([
        #("kind", json.string("Generic")),
        #(
          "children",
          json.array(children, fn(entry) {
            array([json.int(entry.0), atom_json(entry.1)])
          }),
        ),
      ])
    change.ValueField(value) -> concrete_json("Value", value)
    change.OptionalField(value) -> concrete_json("Optional", value)
  }
}

fn concrete_json(kind: String, value: optional_field.FieldChange) -> Json {
  json.object([
    #("kind", json.string(kind)),
    #(
      "moves",
      json.array(value.moves, fn(entry) {
        array([atom_json(entry.0), atom_json(entry.1)])
      }),
    ),
    #(
      "children",
      json.array(value.child_changes, fn(entry) {
        array([register_json(entry.0), atom_json(entry.1)])
      }),
    ),
    #(
      "replacement",
      nullable(value.replacement, fn(value) {
        json.object([
          #("wasEmpty", json.bool(value.was_empty)),
          #("source", nullable(value.source, register_json)),
          #("detach", atom_json(value.detach_id)),
        ])
      }),
    ),
  ])
}

fn register_json(value: optional_field.RegisterId) -> Json {
  case value {
    optional_field.Active -> json.string("active")
    optional_field.Detached(id) -> atom_json(id)
  }
}

pub fn delta_json(value: forest.Delta) -> Json {
  let data = forest.delta_data(value)
  json.object([
    #("latestRevision", nullable(data.latest_revision, revision_json)),
    #("fields", delta_fields_json(data.fields)),
    #("build", json.array(data.build, build_json)),
    #("refreshers", json.array(data.refreshers, build_json)),
    #(
      "global",
      json.array(data.global, fn(entry) {
        json.object([
          #("id", atom_json(entry.id)),
          #("fields", delta_fields_json(entry.fields)),
        ])
      }),
    ),
    #(
      "rename",
      json.array(data.rename, fn(entry) {
        json.object([
          #("oldId", atom_json(entry.old_id)),
          #("newId", atom_json(entry.new_id)),
          #("count", json.int(entry.count)),
        ])
      }),
    ),
    #("destroy", json.array(data.destroy, destroy_json)),
  ])
}

fn delta_fields_json(values: List(#(String, forest.FieldDelta))) -> Json {
  json.array(values, fn(entry) {
    array([
      json.string(entry.0),
      json.object([
        #(
          "marks",
          json.array(entry.1.marks, fn(mark) {
            json.object([
              #("count", json.int(mark.count)),
              #("attach", nullable(mark.attach, atom_json)),
              #("detach", nullable(mark.detach, atom_json)),
              #("fields", delta_fields_json(mark.fields)),
            ])
          }),
        ),
      ]),
    ])
  })
}

pub fn native(value: Result(a, types.TreeError)) -> Result(a, String) {
  result.map_error(value, string.inspect)
}

pub type Revisions =
  List(#(StableId, Int))

pub fn wire_revision(
  id: StableId,
  revisions: Revisions,
) -> Result(Int, String) {
  list.key_find(revisions, id)
  |> result.map_error(fn(_) { "revision is not in the supplied codec context" })
}

pub fn wire_atom(
  id: types.AtomId,
  revisions: Revisions,
) -> Result(Json, String) {
  wire_tagged_atom(id, revisions, None)
}

fn wire_tagged_atom(
  id: types.AtomId,
  revisions: Revisions,
  tagged_revision: Option(StableId),
) -> Result(Json, String) {
  case id.revision {
    None -> Ok(json.int(id.local_id))
    Some(revision) if Some(revision) == tagged_revision ->
      Ok(json.int(id.local_id))
    Some(revision) -> {
      use encoded <- result.try(wire_revision(revision, revisions))
      Ok(array([json.int(id.local_id), json.int(encoded)]))
    }
  }
}

pub fn wire(
  value: change.Changeset,
  revisions: Revisions,
) -> Result(Json, String) {
  wire_tagged(value, revisions, None)
}

pub fn wire_tagged(
  value: change.Changeset,
  revisions: Revisions,
  tagged_revision: Option(StableId),
) -> Result(Json, String) {
  let data = change.to_data(value)
  use _ <- result.try(case tagged_revision {
    None -> Ok(Nil)
    Some(tagged) ->
      case data.revisions {
        [change.RevisionInfo(revision, None)] if revision == tagged -> Ok(Nil)
        _ -> Error("tagged change must contain only its commit revision")
      }
  })
  use fields <- result.try(wire_fields(
    data.fields,
    data,
    revisions,
    tagged_revision,
  ))
  use revision_data <- result.try(
    data.revisions
    |> list.filter(fn(info) { Some(info.revision) != tagged_revision })
    |> list.try_map(fn(info) {
      use revision <- result.try(wire_revision(info.revision, revisions))
      use rollback <- result.try(case info.rollback_of {
        None -> Ok([])
        Some(id) -> {
          use id <- result.try(wire_revision(id, revisions))
          Ok([#("rollbackOf", json.int(id))])
        }
      })
      Ok(json.object([#("revision", json.int(revision)), ..rollback]))
    }),
  )
  use builds <- result.try(wire_builds(data.builds, revisions, tagged_revision))
  use refreshers <- result.try(wire_builds(
    data.refreshers,
    revisions,
    tagged_revision,
  ))
  case data.destroys {
    [] -> {
      let members = [#("maxId", json.int(data.max_local_id))]
      let members = case revision_data {
        [] -> members
        _ -> list.append(members, [#("revisions", array(revision_data))])
      }
      let members = list.append(members, [#("changes", fields)])
      let members = case builds {
        None -> members
        Some(value) -> list.append(members, [#("builds", value)])
      }
      let members = case refreshers {
        None -> members
        Some(value) -> list.append(members, [#("refreshers", value)])
      }
      Ok(json.object(members))
    }
    _ -> Error("the encoded fixture profile excludes destroy-bearing changes")
  }
}

fn wire_fields(
  fields: List(#(String, change.FieldChange)),
  data: change.ChangeData,
  revisions: Revisions,
  tagged_revision: Option(StableId),
) -> Result(Json, String) {
  use encoded <- result.try(
    list.try_map(fields, fn(entry) {
      use #(kind, payload) <- result.try(case entry.1 {
        change.ValueField(field) ->
          wire_concrete(field, data, revisions, tagged_revision)
          |> result.map(fn(encoded) { #("Value", encoded) })
        change.OptionalField(field) ->
          wire_concrete(field, data, revisions, tagged_revision)
          |> result.map(fn(encoded) { #("Optional", encoded) })
        change.GenericField(children) -> {
          use children <- result.try(
            list.try_map(children, fn(child) {
              use node <- result.try(
                wire_node(child.1, data, revisions, tagged_revision, []),
              )
              Ok(array([json.int(child.0), node]))
            }),
          )
          Ok(#("ModularEditBuilder.Generic", array(children)))
        }
      })
      Ok(
        json.object([
          #("fieldKey", json.string(entry.0)),
          #("fieldKind", json.string(kind)),
          #("change", payload),
        ]),
      )
    }),
  )
  Ok(array(encoded))
}

fn wire_concrete(
  field: optional_field.FieldChange,
  data: change.ChangeData,
  revisions: Revisions,
  tagged_revision: Option(StableId),
) -> Result(Json, String) {
  use moves <- result.try(
    list.try_map(field.moves, fn(entry) {
      use first <- result.try(wire_tagged_atom(
        entry.0,
        revisions,
        tagged_revision,
      ))
      use second <- result.try(wire_tagged_atom(
        entry.1,
        revisions,
        tagged_revision,
      ))
      Ok(array([first, second]))
    }),
  )
  use children <- result.try(
    list.try_map(field.child_changes, fn(entry) {
      use register <- result.try(wire_register(
        entry.0,
        revisions,
        tagged_revision,
      ))
      use node <- result.try(
        wire_node(entry.1, data, revisions, tagged_revision, []),
      )
      Ok(array([register, node]))
    }),
  )
  use replacement <- result.try(case field.replacement {
    None -> Ok([])
    Some(value) -> {
      use detach <- result.try(wire_tagged_atom(
        value.detach_id,
        revisions,
        tagged_revision,
      ))
      use source <- result.try(case value.source {
        None -> Ok([])
        Some(value) -> {
          use value <- result.try(wire_register(
            value,
            revisions,
            tagged_revision,
          ))
          Ok([#("s", value)])
        }
      })
      Ok([
        #(
          "r",
          json.object([
            #("e", json.bool(value.was_empty)),
            #("d", detach),
            ..source
          ]),
        ),
      ])
    }
  })
  let members = case moves {
    [] -> replacement
    _ -> [#("m", array(moves)), ..replacement]
  }
  let members = case children {
    [] -> members
    _ -> list.append(members, [#("c", array(children))])
  }
  Ok(json.object(members))
}

fn wire_register(
  value: optional_field.RegisterId,
  revisions: Revisions,
  tagged_revision: Option(StableId),
) -> Result(Json, String) {
  case value {
    optional_field.Active -> Ok(json.null())
    optional_field.Detached(id) ->
      wire_tagged_atom(id, revisions, tagged_revision)
  }
}

fn wire_node(
  id: types.AtomId,
  data: change.ChangeData,
  revisions: Revisions,
  tagged_revision: Option(StableId),
  visited: List(types.AtomId),
) -> Result(Json, String) {
  case list.contains(visited, id) {
    True -> Error("cyclic node alias in encoded change")
    False ->
      case list.key_find(data.aliases, id) {
        Ok(next) ->
          wire_node(next, data, revisions, tagged_revision, [id, ..visited])
        Error(Nil) -> {
          use node <- result.try(
            list.key_find(data.nodes, id)
            |> result.map_error(fn(_) { "missing encoded child node" }),
          )
          case node.fields {
            [] -> Ok(json.object([]))
            fields -> {
              use fields <- result.try(wire_fields(
                fields,
                data,
                revisions,
                tagged_revision,
              ))
              Ok(json.object([#("fieldChanges", fields)]))
            }
          }
        }
      }
  }
}

fn wire_builds(
  builds: List(forest.Build),
  revisions: Revisions,
  tagged_revision: Option(StableId),
) -> Result(Option(Json), String) {
  case builds {
    [] -> Ok(None)
    _ -> {
      use keyed <- result.try(
        list.try_map(builds, fn(build) {
          use revision <- result.try(case build.id.revision {
            None -> Ok(-1)
            Some(revision) if Some(revision) == tagged_revision -> Ok(-1)
            Some(revision) -> wire_revision(revision, revisions)
          })
          Ok(#(revision, build))
        }),
      )
      let keyed =
        list.sort(keyed, fn(left, right) {
          case int.compare(left.0, right.0) {
            order.Eq -> int.compare(left.1.id.local_id, right.1.id.local_id)
            compared -> compared
          }
        })
      use trees <- result.try(
        list.try_map(keyed, fn(entry) {
          list.try_map(entry.1.trees, fn(tree) {
            wire_tree(tree)
            |> result.map(fn(tree) { array([json.int(1), tree]) })
          })
        })
        |> result.map(list.flatten),
      )
      let indexed =
        list.index_map(keyed, fn(entry, index) {
          #(entry.0, array([json.int(entry.1.id.local_id), json.int(index)]))
        })
      let groups =
        list.fold(indexed, [], fn(groups, entry) {
          case groups {
            [#(revision, entries), ..rest] if revision == entry.0 -> [
              #(revision, [entry.1, ..entries]),
              ..rest
            ]
            _ -> [#(entry.0, [entry.1]), ..groups]
          }
        })
      let groups =
        list.reverse(groups)
        |> list.map(fn(group) {
          let entries = array(list.reverse(group.1))
          case group.0 {
            -1 -> array([entries])
            revision -> array([entries, json.int(revision)])
          }
        })
      Ok(
        Some(
          json.object([
            #("builds", array(groups)),
            #(
              "trees",
              json.object([
                #("version", json.int(2)),
                #("identifiers", array([])),
                #(
                  "shapes",
                  array([
                    json.object([
                      #("c", json.object([#("extraFields", json.int(1))])),
                    ]),
                    json.object([#("a", json.int(0))]),
                  ]),
                ),
                #("data", array(trees)),
              ]),
            ),
          ]),
        ),
      )
    }
  }
}

fn wire_tree(value: types.TreeValue) -> Result(Json, String) {
  case value {
    types.StringValue(value) ->
      Ok(
        array([
          json.string("com.fluidframework.leaf.string"),
          json.bool(True),
          json.string(value),
          array([]),
        ]),
      )
    types.NumberValue(value) ->
      Ok(
        array([
          json.string("com.fluidframework.leaf.number"),
          json.bool(True),
          json.float(value),
          array([]),
        ]),
      )
    types.BooleanValue(value) ->
      Ok(
        array([
          json.string("com.fluidframework.leaf.boolean"),
          json.bool(True),
          json.bool(value),
          array([]),
        ]),
      )
    types.NullValue ->
      Ok(
        array([
          json.string("com.fluidframework.leaf.null"),
          json.bool(True),
          json.null(),
          array([]),
        ]),
      )
    types.ObjectValue(identifier, fields) -> {
      use fields <- result.try(
        list.try_map(fields, fn(field) {
          use value <- result.try(wire_tree(field.1))
          Ok([json.string(field.0), value])
        }),
      )
      Ok(
        array([
          json.string(identifier),
          json.bool(False),
          fields |> list.flatten |> array,
        ]),
      )
    }
    types.MapValue(_, _) ->
      Error("the encoded fixture profile excludes map builds")
  }
}
