import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/fluid_ids
import watershed/json_ot.{type JsonValue, VNull, VObject}
import watershed/tree/change
import watershed/tree/change_fixture_codec as codec
import watershed/tree/codec as tree_codec
import watershed/tree/forest
import watershed/tree/optional_field
import watershed/tree/sequence_field
import watershed/tree/sequence_field/moves
import watershed/tree/types

type Context {
  Context(
    revisions: List(#(Int, fluid_ids.StableId)),
    identity_order: change.IdentityOrder,
  )
}

type Decoded {
  Decoded(
    tagged: List(change.TaggedChange),
    context: Context,
    operation: String,
    operands: JsonValue,
  )
}

pub fn run(input: Json) -> Result(Json, String) {
  use value <- result.try(codec.parse(input))
  use scenarios <- result.try(codec.field(value, "scenarios", codec.items))
  use observations <- result.try(list.try_map(scenarios, run_scenario))
  Ok(
    json.object([
      #("observations", json.array(observations, fn(value) { value })),
    ]),
  )
}

fn run_scenario(value: JsonValue) -> Result(Json, String) {
  use id <- result.try(codec.field(value, "id", codec.text))
  use decoded <- result.try(
    decode_scenario(value)
    |> result.map_error(fn(error) { id <> " decode: " <> error }),
  )
  use #(output, trace, revision) <- result.try(
    run_operation(decoded)
    |> result.map_error(fn(error) { id <> " operation: " <> error }),
  )
  use delta <- result.try(
    change.into_delta(change.TaggedChange(revision, None, output))
    |> codec.native,
  )
  use graph <- result.try(graph_json(output, decoded.context))
  use coordination <- result.try(trace_json(trace, decoded.context))
  use conversion <- result.try(conversion_json(trace, decoded.context))
  Ok(
    json.object([
      #("id", json.string(id)),
      #("executed", json.bool(True)),
      #(
        "fieldKinds",
        json.array(["ModularEditBuilder.Generic", "Sequence"], json.string),
      ),
      #(
        "result",
        json.object([
          #("graph", graph),
          #("delta", delta_json(delta, decoded.context)),
          #("conversion", conversion),
          #("coordination", coordination),
        ]),
      ),
    ]),
  )
}

fn decode_scenario(value: JsonValue) -> Result(Decoded, String) {
  use operation <- result.try(codec.field(value, "operation", codec.text))
  use operands <- result.try(codec.get(value, "operands"))
  use context <- result.try(decode_context(value))
  use changes <- result.try(codec.field(operands, "changes", codec.items))
  use tagged <- result.try(
    list.try_map(changes, fn(value) {
      use revision <- result.try(
        codec.field(value, "revision", decode_revision(_, context)),
      )
      use graph <- result.try(codec.get(value, "change"))
      use change <- result.try(decode_graph(graph, context))
      Ok(change.TaggedChange(Some(revision), None, change))
    }),
  )
  Ok(Decoded(tagged, context, operation, operands))
}

fn decode_context(value: JsonValue) -> Result(Context, String) {
  use mappings <- result.try(codec.field(value, "revisions", codec.items))
  use revisions <- result.try(
    list.try_map(mappings, fn(value) {
      use encoded <- result.try(codec.field(value, "encoded", codec.integer))
      use stable <- result.try(codec.field(value, "stable", codec.text))
      use stable <- result.try(
        fluid_ids.stable_id(stable) |> result.map_error(string.inspect),
      )
      Ok(#(encoded, stable))
    }),
  )
  use compressor_value <- result.try(codec.get(value, "compressor"))
  use session <- result.try(codec.field(
    compressor_value,
    "sessionId",
    codec.text,
  ))
  use session <- result.try(
    fluid_ids.session_id(session) |> result.map_error(string.inspect),
  )
  use serialized <- result.try(codec.field(
    compressor_value,
    "serialized",
    codec.text,
  ))
  use compressor <- result.try(
    fluid_ids.deserialize(json.string(serialized), session)
    |> result.map_error(string.inspect),
  )
  use identity_order <- result.try(
    tree_codec.identity_order(
      list.map(revisions, fn(entry) { entry.1 }),
      compressor,
      "array modular fixture",
    )
    |> codec.native,
  )
  Ok(Context(revisions, identity_order))
}

fn decode_revision(
  value: JsonValue,
  context: Context,
) -> Result(fluid_ids.StableId, String) {
  use encoded <- result.try(codec.integer(value))
  list.key_find(context.revisions, encoded)
  |> result.map_error(fn(_) { "unknown encoded revision" })
}

fn decode_optional_revision(
  value: JsonValue,
  context: Context,
) -> Result(Option(fluid_ids.StableId), String) {
  case value {
    VNull -> Ok(None)
    _ -> decode_revision(value, context) |> result.map(Some)
  }
}

fn decode_atom(
  value: JsonValue,
  context: Context,
) -> Result(types.AtomId, String) {
  use revision <- result.try(
    codec.field(value, "revision", decode_optional_revision(_, context)),
  )
  use local_id <- result.try(codec.field(value, "localId", codec.integer))
  Ok(types.AtomId(revision, local_id))
}

fn decode_graph(
  value: JsonValue,
  context: Context,
) -> Result(change.Changeset, String) {
  use max_local_id <- result.try(codec.field(value, "maxLocalId", codec.integer))
  use revisions <- result.try(
    codec.field(value, "revisions", fn(value) {
      codec.many(value, fn(value) {
        use revision <- result.try(
          codec.field(value, "revision", decode_revision(_, context)),
        )
        use rollback <- result.try(
          codec.field(value, "rollbackOf", decode_optional_revision(_, context)),
        )
        Ok(change.RevisionInfo(revision, rollback))
      })
    }),
  )
  use fields <- result.try(
    codec.field(value, "fields", decode_fields(_, context)),
  )
  use nodes <- result.try(
    codec.field(value, "nodes", fn(value) {
      codec.many(value, fn(value) {
        use #(id, node) <- result.try(codec.pair(value))
        use id <- result.try(decode_atom(id, context))
        use fields <- result.try(
          codec.field(node, "fields", decode_fields(_, context)),
        )
        Ok(#(id, change.NodeChange(fields)))
      })
    }),
  )
  use parents <- result.try(
    codec.field(value, "parents", fn(value) {
      codec.many(value, fn(value) {
        use #(id, parent) <- result.try(codec.pair(value))
        use id <- result.try(decode_atom(id, context))
        use node <- result.try(
          codec.field(parent, "node", fn(value) {
            case value {
              VNull -> Ok(None)
              _ -> decode_atom(value, context) |> result.map(Some)
            }
          }),
        )
        use field <- result.try(codec.field(parent, "field", codec.text))
        Ok(#(id, change.ParentField(node, field)))
      })
    }),
  )
  use aliases <- result.try(
    codec.field(value, "aliases", fn(value) {
      codec.many(value, fn(value) {
        use #(source, target) <- result.try(codec.pair(value))
        use source <- result.try(decode_atom(source, context))
        use target <- result.try(decode_atom(target, context))
        Ok(#(source, target))
      })
    }),
  )
  use _ <- result.try(require_empty(value, "builds"))
  use _ <- result.try(require_empty(value, "refreshers"))
  use _ <- result.try(require_empty(value, "destroys"))
  use expected_keys <- result.try(
    codec.field(value, "crossFieldKeys", decode_cross_field_keys(_, context)),
  )
  use decoded <- result.try(
    change.from_data(
      change.ChangeData(
        max_local_id:,
        revisions:,
        fields:,
        nodes:,
        parents:,
        aliases:,
        builds: [],
        refreshers: [],
        destroys: [],
        cross_field_keys: expected_keys,
      ),
      context.identity_order,
    )
    |> codec.native,
  )
  use actual_keys <- result.try(
    change.cross_field_keys(decoded) |> codec.native,
  )
  case actual_keys == expected_keys {
    True -> Ok(decoded)
    False -> Error("cross-field key ownership does not match the fields")
  }
}

fn require_empty(value: JsonValue, key: String) -> Result(Nil, String) {
  use values <- result.try(codec.field(value, key, codec.items))
  case values {
    [] -> Ok(Nil)
    _ -> Error(key <> " are not supported by this modular fixture")
  }
}

fn decode_fields(
  value: JsonValue,
  context: Context,
) -> Result(List(#(String, change.FieldChange)), String) {
  codec.many(value, fn(value) {
    use #(key, field) <- result.try(codec.pair(value))
    use key <- result.try(codec.text(key))
    use kind <- result.try(codec.field(field, "kind", codec.text))
    use payload <- result.try(codec.get(field, "change"))
    use field <- result.try(case kind {
      "Generic" ->
        codec.field(payload, "children", fn(value) {
          codec.many(value, fn(value) {
            use #(index, id) <- result.try(codec.pair(value))
            use index <- result.try(codec.integer(index))
            use id <- result.try(decode_atom(id, context))
            Ok(#(index, id))
          })
        })
        |> result.map(change.GenericField)
      "Sequence" ->
        decode_sequence(payload, context) |> result.map(change.SequenceField)
      _ -> Error("unsupported modular field kind: " <> kind)
    })
    Ok(#(key, field))
  })
}

fn decode_sequence(
  value: JsonValue,
  context: Context,
) -> Result(sequence_field.Changeset, String) {
  use marks <- result.try(codec.many(value, decode_mark(_, context)))
  sequence_field.from_marks(marks) |> codec.native
}

fn decode_mark(
  value: JsonValue,
  context: Context,
) -> Result(sequence_field.Mark, String) {
  use count <- result.try(codec.field(value, "count", codec.integer))
  use cell_id <- result.try(
    optional_member(value, "cellId", decode_atom(_, context)),
  )
  use child <- result.try(
    optional_member(value, "changes", decode_atom(_, context)),
  )
  use effect <- result.try(case member(value, "type") {
    None -> Ok(sequence_field.Noop)
    Some(type_value) -> decode_effect(type_value, value, context)
  })
  Ok(sequence_field.Mark(count, cell_id, effect, child))
}

fn decode_effect(
  type_value: JsonValue,
  value: JsonValue,
  context: Context,
) -> Result(sequence_field.Effect, String) {
  use kind <- result.try(codec.text(type_value))
  use effect_id <- result.try(optional_effect_atom(value, context))
  case kind, effect_id {
    "Insert", Some(id) -> Ok(sequence_field.Attach(sequence_field.Insert(id)))
    "MoveIn", Some(id) -> {
      use endpoint <- result.try(
        optional_member(value, "finalEndpoint", decode_atom(_, context)),
      )
      Ok(sequence_field.Attach(sequence_field.MoveIn(id, endpoint)))
    }
    "Remove", Some(id) -> {
      use id_override <- result.try(
        optional_member(value, "idOverride", decode_atom(_, context)),
      )
      Ok(sequence_field.Detach(sequence_field.Remove(id, id_override)))
    }
    "MoveOut", Some(id) -> {
      use endpoint <- result.try(
        optional_member(value, "finalEndpoint", decode_atom(_, context)),
      )
      use id_override <- result.try(
        optional_member(value, "idOverride", decode_atom(_, context)),
      )
      Ok(
        sequence_field.Detach(sequence_field.MoveOut(id, endpoint, id_override)),
      )
    }
    "Rename", _ ->
      codec.field(value, "idOverride", decode_atom(_, context))
      |> result.map(sequence_field.Rename)
    _, _ -> Error("unsupported or incomplete sequence mark: " <> kind)
  }
}

fn optional_effect_atom(
  value: JsonValue,
  context: Context,
) -> Result(Option(types.AtomId), String) {
  case member(value, "id") {
    None -> Ok(None)
    Some(id) -> {
      use local_id <- result.try(codec.integer(id))
      use revision <- result.try(
        optional_member(value, "revision", decode_revision(_, context)),
      )
      Ok(Some(types.AtomId(revision, local_id)))
    }
  }
}

fn optional_member(
  value: JsonValue,
  key: String,
  decode: fn(JsonValue) -> Result(a, String),
) -> Result(Option(a), String) {
  case member(value, key) {
    None | Some(VNull) -> Ok(None)
    Some(value) -> decode(value) |> result.map(Some)
  }
}

fn member(value: JsonValue, key: String) -> Option(JsonValue) {
  case value {
    VObject(entries) ->
      case list.key_find(entries, key) {
        Ok(value) -> Some(value)
        Error(Nil) -> None
      }
    _ -> None
  }
}

fn decode_cross_field_keys(
  value: JsonValue,
  context: Context,
) -> Result(List(change.CrossFieldKey), String) {
  codec.many(value, fn(value) {
    use target <- result.try(codec.field(value, "target", codec.text))
    use revision <- result.try(
      codec.field(value, "revision", decode_optional_revision(_, context)),
    )
    use local_id <- result.try(codec.field(value, "localId", codec.integer))
    use count <- result.try(codec.field(value, "count", codec.integer))
    use field <- result.try(
      codec.field(value, "field", fn(value) {
        use node <- result.try(
          codec.field(value, "node", fn(value) {
            case value {
              VNull -> Ok(None)
              _ -> decode_atom(value, context) |> result.map(Some)
            }
          }),
        )
        use field <- result.try(codec.field(value, "field", codec.text))
        Ok(moves.FieldId(node, field))
      }),
    )
    use side <- result.try(case target {
      "source" -> Ok(moves.Source)
      "destination" -> Ok(moves.Destination)
      _ -> Error("unsupported cross-field target")
    })
    Ok(change.CrossFieldKey(moves.Key(side, revision, local_id), count, field))
  })
}

fn run_operation(
  decoded: Decoded,
) -> Result(
  #(change.Changeset, List(moves.TraceEvent), Option(fluid_ids.StableId)),
  String,
) {
  case decoded.operation, decoded.tagged {
    "compose", changes ->
      change.compose_with_trace(changes)
      |> codec.native
      |> result.map(fn(output) { #(output.0, output.1, None) })
    "invert", [tagged] -> {
      use rollback <- result.try(codec.field(
        decoded.operands,
        "isRollback",
        codec.boolean,
      ))
      use revision <- result.try(
        codec.field(decoded.operands, "inverseRevision", decode_revision(
          _,
          decoded.context,
        )),
      )
      change.invert_with_trace(tagged, rollback, revision)
      |> codec.native
      |> result.map(fn(output) { #(output.0, output.1, Some(revision)) })
    }
    "rebase", [authored, base] -> {
      use revisions <- result.try(
        codec.field(decoded.operands, "revisionMetadata", fn(value) {
          codec.many(value, fn(value) {
            use revision <- result.try(
              codec.field(value, "revision", decode_revision(_, decoded.context)),
            )
            use rollback <- result.try(
              codec.field(value, "rollbackOf", decode_optional_revision(
                _,
                decoded.context,
              )),
            )
            Ok(change.RevisionInfo(revision, rollback))
          })
        }),
      )
      use context <- result.try(
        change.rebase_context(revisions) |> codec.native,
      )
      change.rebase_with_trace(authored, base, context)
      |> codec.native
      |> result.map(fn(output) {
        let change.TaggedChange(revision, _, _) = authored
        #(output.0, output.1, revision)
      })
    }
    _, _ -> Error("invalid modular operation operands")
  }
}

fn graph_json(
  value: change.Changeset,
  context: Context,
) -> Result(Json, String) {
  let data = change.to_data(value)
  use fields <- result.try(fields_json(data.fields, context))
  use nodes <- result.try(
    list.try_map(data.nodes, fn(entry) {
      use id <- result.try(atom_json(entry.0, context))
      use fields <- result.try(fields_json(entry.1.fields, context))
      Ok(codec.array([id, json.object([#("fields", fields)])]))
    }),
  )
  use parents <- result.try(
    list.try_map(data.parents, fn(entry) {
      use id <- result.try(atom_json(entry.0, context))
      use parent <- result.try(optional_atom_json(entry.1.parent, context))
      Ok(
        codec.array([
          id,
          json.object([
            #("node", parent),
            #("field", json.string(entry.1.field)),
          ]),
        ]),
      )
    }),
  )
  use aliases <- result.try(
    list.try_map(data.aliases, fn(entry) {
      use source <- result.try(atom_json(entry.0, context))
      use target <- result.try(atom_json(entry.1, context))
      Ok(codec.array([source, target]))
    }),
  )
  use keys <- result.try(change.cross_field_keys(value) |> codec.native)
  use keys <- result.try(list.try_map(keys, cross_field_key_json(_, context)))
  use builds <- result.try(list.try_map(data.builds, build_json(_, context)))
  use refreshers <- result.try(
    list.try_map(data.refreshers, build_json(_, context)),
  )
  use destroys <- result.try(
    list.try_map(data.destroys, fn(value) {
      use id <- result.try(atom_json(value.id, context))
      Ok(codec.array([id, json.int(value.count)]))
    }),
  )
  Ok(
    json.object([
      #("maxLocalId", json.int(data.max_local_id)),
      #("revisions", json.array(data.revisions, revision_info_json(_, context))),
      #("fields", fields),
      #("nodes", codec.array(nodes)),
      #("parents", codec.array(parents)),
      #("aliases", codec.array(aliases)),
      #("crossFieldKeys", codec.array(keys)),
      #("builds", codec.array(builds)),
      #("refreshers", codec.array(refreshers)),
      #("destroys", codec.array(destroys)),
    ]),
  )
}

pub fn graph_json_with_compressor(
  value: change.Changeset,
  compressor: fluid_ids.Compressor,
) -> Result(Json, String) {
  use revisions <- result.try(
    list.try_map(change.identity_revisions(value), fn(revision) {
      use encoded <- result.try(
        tree_codec.encode_stable_revision(
          revision,
          tree_codec.EncodeContext(tree_codec.Fluid310, compressor, None),
          "array codec fixture revision",
        )
        |> codec.native,
      )
      Ok(#(encoded, revision))
    }),
  )
  use order <- result.try(
    tree_codec.identity_order(
      change.identity_revisions(value),
      compressor,
      "array codec fixture revisions",
    )
    |> codec.native,
  )
  graph_json(value, Context(revisions, order))
}

fn build_json(value: forest.Build, context: Context) -> Result(Json, String) {
  use id <- result.try(atom_json(value.id, context))
  Ok(
    codec.array([
      id,
      json.array(value.trees, source_tree_json),
    ]),
  )
}

pub fn source_tree_json(value: types.TreeValue) -> Json {
  case value {
    types.StringValue(value) ->
      json.object([
        #("type", json.string("com.fluidframework.leaf.string")),
        #("value", json.string(value)),
      ])
    types.NumberValue(value) -> {
      let encoded = case int.to_float(float.truncate(value)) == value {
        True -> json.int(float.truncate(value))
        False -> json.float(value)
      }
      json.object([
        #("type", json.string("com.fluidframework.leaf.number")),
        #("value", encoded),
      ])
    }
    types.BooleanValue(value) ->
      json.object([
        #("type", json.string("com.fluidframework.leaf.boolean")),
        #("value", json.bool(value)),
      ])
    types.NullValue ->
      json.object([#("type", json.string("com.fluidframework.leaf.null"))])
    types.ObjectValue(identifier, fields)
    | types.MapValue(identifier, fields) ->
      json.object([
        #("type", json.string(identifier)),
        #("fields", source_fields_json(fields)),
      ])
    types.ArrayValue(identifier, elements) -> {
      let members = [#("type", json.string(identifier))]
      let members = case elements {
        [] -> members
        _ ->
          list.append(members, [
            #(
              "fields",
              json.object([
                #("", json.array(elements, source_tree_json)),
              ]),
            ),
          ])
      }
      json.object(members)
    }
  }
}

fn source_fields_json(fields: List(#(String, types.TreeValue))) -> Json {
  json.object(
    list.map(fields, fn(field) {
      #(field.0, json.array([field.1], source_tree_json))
    }),
  )
}

fn fields_json(
  fields: List(#(String, change.FieldChange)),
  context: Context,
) -> Result(Json, String) {
  use fields <- result.try(
    list.try_map(fields, fn(entry) {
      use field <- result.try(field_json(entry.1, context))
      Ok(codec.array([json.string(entry.0), field]))
    }),
  )
  Ok(codec.array(fields))
}

fn field_json(
  field: change.FieldChange,
  context: Context,
) -> Result(Json, String) {
  case field {
    change.GenericField(children) -> {
      use children <- result.try(
        list.try_map(children, fn(child) {
          use id <- result.try(atom_json(child.1, context))
          Ok(codec.array([json.int(child.0), id]))
        }),
      )
      Ok(
        json.object([
          #("kind", json.string("Generic")),
          #("change", json.object([#("children", codec.array(children))])),
        ]),
      )
    }
    change.SequenceField(sequence) -> {
      use marks <- result.try(
        list.try_map(sequence_field.to_marks(sequence), sequence_mark_json(
          _,
          context,
        )),
      )
      Ok(
        json.object([
          #("kind", json.string("Sequence")),
          #("change", codec.array(marks)),
        ]),
      )
    }
    change.ValueField(value) -> optional_field_json("Value", value, context)
    change.OptionalField(value) ->
      optional_field_json("Optional", value, context)
  }
}

fn optional_field_json(
  kind: String,
  field: optional_field.FieldChange,
  context: Context,
) -> Result(Json, String) {
  use moves <- result.try(
    list.try_map(field.moves, fn(entry) {
      use source <- result.try(atom_json(entry.0, context))
      use destination <- result.try(atom_json(entry.1, context))
      Ok(codec.array([source, destination]))
    }),
  )
  use children <- result.try(
    list.try_map(field.child_changes, fn(entry) {
      use child <- result.try(atom_json(entry.1, context))
      use register <- result.try(case entry.0 {
        optional_field.Active -> Ok(json.null())
        optional_field.Detached(id) -> atom_json(id, context)
      })
      Ok(codec.array([register, child]))
    }),
  )
  use replacement <- result.try(case field.replacement {
    None -> Ok(json.null())
    Some(value) -> {
      use destination <- result.try(atom_json(value.detach_id, context))
      use source <- result.try(case value.source {
        None -> Ok(json.null())
        Some(optional_field.Active) -> Ok(json.null())
        Some(optional_field.Detached(id)) -> atom_json(id, context)
      })
      Ok(
        json.object([
          #("isEmpty", json.bool(value.was_empty)),
          #("dst", destination),
          #("src", source),
        ]),
      )
    }
  })
  Ok(
    json.object([
      #("kind", json.string(kind)),
      #(
        "change",
        json.object([
          #("moves", codec.array(moves)),
          #("childChanges", codec.array(children)),
          #("valueReplace", replacement),
        ]),
      ),
    ]),
  )
}

fn sequence_mark_json(
  mark: sequence_field.Mark,
  context: Context,
) -> Result(Json, String) {
  use cell <- result.try(case mark.cell_id {
    None -> Ok([])
    Some(id) ->
      atom_json(id, context) |> result.map(fn(id) { [#("cellId", id)] })
  })
  use child <- result.try(case mark.child {
    None -> Ok([])
    Some(id) ->
      atom_json(id, context) |> result.map(fn(id) { [#("changes", id)] })
  })
  use effect <- result.try(sequence_effect_members(mark.effect, context))
  Ok(
    json.object([
      #("count", json.int(mark.count)),
      ..list.flatten([effect, cell, child])
    ]),
  )
}

fn sequence_effect_members(
  effect: sequence_field.Effect,
  context: Context,
) -> Result(List(#(String, Json)), String) {
  case effect {
    sequence_field.Noop -> Ok([])
    sequence_field.Rename(id) -> {
      use id <- result.try(atom_json(id, context))
      Ok([#("type", json.string("Rename")), #("idOverride", id)])
    }
    sequence_field.Attach(sequence_field.Insert(id)) -> {
      use revision <- result.try(optional_revision_json(id.revision, context))
      Ok([
        #("type", json.string("Insert")),
        #("id", json.int(id.local_id)),
        #("revision", revision),
      ])
    }
    sequence_field.Attach(sequence_field.MoveIn(id, endpoint)) -> {
      use members <- result.try(move_members("MoveIn", id, endpoint, context))
      Ok(members)
    }
    sequence_field.Detach(sequence_field.Remove(id, id_override)) -> {
      use members <- result.try(move_members("Remove", id, None, context))
      use override <- result.try(optional_named_atom(
        "idOverride",
        id_override,
        context,
      ))
      Ok(list.append(members, override))
    }
    sequence_field.Detach(sequence_field.MoveOut(id, endpoint, id_override)) -> {
      use members <- result.try(move_members("MoveOut", id, endpoint, context))
      use override <- result.try(optional_named_atom(
        "idOverride",
        id_override,
        context,
      ))
      Ok(list.append(members, override))
    }
    sequence_field.AttachAndDetach(attach, detach) -> {
      use attach <- result.try(sequence_effect_members(
        sequence_field.Attach(attach),
        context,
      ))
      use detach <- result.try(sequence_effect_members(
        sequence_field.Detach(detach),
        context,
      ))
      Ok([
        #("type", json.string("AttachAndDetach")),
        #("attach", json.object(attach)),
        #("detach", json.object(detach)),
      ])
    }
  }
}

fn move_members(
  kind: String,
  id: types.AtomId,
  endpoint: Option(types.AtomId),
  context: Context,
) -> Result(List(#(String, Json)), String) {
  use revision <- result.try(optional_revision_json(id.revision, context))
  use endpoint <- result.try(optional_named_atom(
    "finalEndpoint",
    endpoint,
    context,
  ))
  Ok([
    #("type", json.string(kind)),
    #("id", json.int(id.local_id)),
    #("revision", revision),
    ..endpoint
  ])
}

fn optional_named_atom(
  name: String,
  value: Option(types.AtomId),
  context: Context,
) -> Result(List(#(String, Json)), String) {
  case value {
    None -> Ok([])
    Some(value) ->
      atom_json(value, context)
      |> result.map(fn(value) { [#(name, value)] })
  }
}

fn revision_info_json(info: change.RevisionInfo, context: Context) -> Json {
  json.object([
    #("revision", encoded_revision_json(info.revision, context)),
    #("rollbackOf", case info.rollback_of {
      None -> json.null()
      Some(revision) -> encoded_revision_json(revision, context)
    }),
  ])
}

fn atom_json(id: types.AtomId, context: Context) -> Result(Json, String) {
  use revision <- result.try(optional_revision_json(id.revision, context))
  Ok(
    json.object([
      #("revision", revision),
      #("localId", json.int(id.local_id)),
    ]),
  )
}

fn optional_atom_json(
  id: Option(types.AtomId),
  context: Context,
) -> Result(Json, String) {
  case id {
    None -> Ok(json.null())
    Some(id) -> atom_json(id, context)
  }
}

fn optional_revision_json(
  revision: Option(fluid_ids.StableId),
  context: Context,
) -> Result(Json, String) {
  case revision {
    None -> Ok(json.null())
    Some(revision) ->
      encoded_revision(revision, context) |> result.map(json.int)
  }
}

fn encoded_revision_json(
  revision: fluid_ids.StableId,
  context: Context,
) -> Json {
  let assert Ok(encoded) = encoded_revision(revision, context)
  json.int(encoded)
}

fn encoded_revision(
  revision: fluid_ids.StableId,
  context: Context,
) -> Result(Int, String) {
  list.find(context.revisions, fn(entry) { entry.1 == revision })
  |> result.map(fn(entry) { entry.0 })
  |> result.map_error(fn(_) { "stable revision is not mapped" })
}

fn cross_field_key_json(
  value: change.CrossFieldKey,
  context: Context,
) -> Result(Json, String) {
  let change.CrossFieldKey(key, count, field) = value
  let moves.Key(side, revision, local_id) = key
  use revision <- result.try(optional_revision_json(revision, context))
  use field <- result.try(field_id_json(field, context))
  Ok(
    json.object([
      #(
        "target",
        json.string(case side {
          moves.Source -> "source"
          moves.Destination -> "destination"
        }),
      ),
      #("revision", revision),
      #("localId", json.int(local_id)),
      #("count", json.int(count)),
      #("field", field),
    ]),
  )
}

fn field_id_json(
  field: moves.FieldId,
  context: Context,
) -> Result(Json, String) {
  use node <- result.try(optional_atom_json(field.parent, context))
  Ok(
    json.object([
      #("node", node),
      #("field", json.string(field.field)),
    ]),
  )
}

fn delta_json(value: forest.Delta, context: Context) -> Json {
  let data = forest.delta_data(value)
  json.object([
    #("fields", delta_fields_json(data.fields, context)),
    #(
      "build",
      json.array(data.build, fn(build) {
        json.object([
          #("id", result.unwrap(atom_json(build.id, context), json.null())),
          #("count", json.int(list.length(build.trees))),
        ])
      }),
    ),
    #(
      "refreshers",
      json.array(data.refreshers, fn(build) {
        json.object([
          #("id", result.unwrap(atom_json(build.id, context), json.null())),
          #("count", json.int(list.length(build.trees))),
        ])
      }),
    ),
    #(
      "global",
      json.array(data.global, fn(entry) {
        json.object([
          #("id", result.unwrap(atom_json(entry.id, context), json.null())),
          #("fields", delta_fields_json(entry.fields, context)),
        ])
      }),
    ),
    #(
      "rename",
      json.array(data.rename, fn(entry) {
        json.object([
          #(
            "oldId",
            result.unwrap(atom_json(entry.old_id, context), json.null()),
          ),
          #(
            "newId",
            result.unwrap(atom_json(entry.new_id, context), json.null()),
          ),
          #("count", json.int(entry.count)),
        ])
      }),
    ),
    #(
      "destroy",
      json.array(data.destroy, fn(entry) {
        json.object([
          #("id", result.unwrap(atom_json(entry.id, context), json.null())),
          #("count", json.int(entry.count)),
        ])
      }),
    ),
  ])
}

fn delta_fields_json(
  fields: List(#(String, forest.FieldDelta)),
  context: Context,
) -> Json {
  json.array(fields, fn(entry) {
    codec.array([
      json.string(entry.0),
      json.object([
        #(
          "marks",
          json.array(entry.1.marks, fn(mark) {
            json.object([
              #("count", json.int(mark.count)),
              #(
                "attach",
                result.unwrap(
                  optional_atom_json(mark.attach, context),
                  json.null(),
                ),
              ),
              #(
                "detach",
                result.unwrap(
                  optional_atom_json(mark.detach, context),
                  json.null(),
                ),
              ),
              #("fields", delta_fields_json(mark.fields, context)),
            ])
          }),
        ),
      ]),
    ])
  })
}

fn trace_json(
  trace: List(moves.TraceEvent),
  context: Context,
) -> Result(Json, String) {
  let initial: #(List(#(#(String, moves.FieldId), Json)), List(Json), Int) = #(
    [],
    [],
    0,
  )
  use #(handlers, managers, _) <- result.try(
    list.try_fold(trace, initial, fn(output, event) {
      let sequence = output.2
      case event {
        moves.HandlerCalled(operation, field) -> {
          use field_json <- result.try(field_id_json(field, context))
          let invocation =
            output.0
            |> list.filter(fn(entry) { entry.0 == #(operation, field) })
            |> list.length
            |> int.add(1)
          let handler = #(
            #(operation, field),
            json.object([
              #("operation", json.string(operation)),
              #("field", field_json),
              #("invocation", json.int(invocation)),
            ]),
          )
          Ok(#([handler, ..output.0], output.1, sequence + 1))
        }
        moves.GenericConverted(_, _, _, _) ->
          Ok(#(output.0, output.1, sequence + 1))
        moves.DependenciesInvalidated(_) ->
          Ok(#(output.0, output.1, sequence + 1))
        moves.RangeRead(field, key, count, dependency, found, length) -> {
          let _ = #(field, key, count, dependency, found, length)
          Ok(#(output.0, output.1, sequence + 1))
        }
        moves.RangeWritten(field, key, count, invalidate) -> {
          use event <- result.try(
            manager_range_json(sequence, "set", field, key, count, context, [
              #("invalidateDependents", json.bool(invalidate)),
            ]),
          )
          Ok(#(output.0, [event, ..output.1], sequence + 1))
        }
        moves.MoveInNotified(field, id) -> {
          use field <- result.try(field_id_json(field, context))
          use id <- result.try(atom_json(id, context))
          let event =
            json.object([
              #("method", json.string("onMoveIn")),
              #("field", field),
              #("id", id),
            ])
          Ok(#(output.0, [event, ..output.1], sequence + 1))
        }
        moves.KeyMoveNotified(field, key, count) -> {
          use event <- result.try(
            manager_range_json(
              sequence,
              "moveKey",
              field,
              key,
              count,
              context,
              [],
            ),
          )
          Ok(#(output.0, [event, ..output.1], sequence + 1))
        }
      }
    }),
  )
  use causal <- result.try(causal_trace_json(trace, context))
  Ok(
    json.object([
      #(
        "handlerCalls",
        output_json(list.reverse(handlers), fn(entry) { entry.1 }),
      ),
      #("managerCalls", codec.array(list.reverse(managers))),
      #("causalCalls", causal),
      #("readEvidence", read_evidence_json(trace)),
    ]),
  )
}

fn causal_trace_json(
  trace: List(moves.TraceEvent),
  context: Context,
) -> Result(Json, String) {
  trace
  |> list.try_fold(#([], []), fn(output, event) {
    case event {
      moves.HandlerCalled(operation, field) -> {
        let invocation =
          output.1
          |> list.filter(fn(entry) { entry == #(operation, field) })
          |> list.length
          |> int.add(1)
        use field_json <- result.try(field_id_json(field, context))
        Ok(
          #(
            list.append(output.0, [
              json.object([
                #("kind", json.string("handler")),
                #("operation", json.string(operation)),
                #("field", field_json),
                #("invocation", json.int(invocation)),
              ]),
            ]),
            [#(operation, field), ..output.1],
          ),
        )
      }
      moves.RangeWritten(field, key, count, invalidate) -> {
        use call <- result.try(
          manager_range_json(0, "set", field, key, count, context, [
            #("invalidateDependents", json.bool(invalidate)),
          ]),
        )
        Ok(#(
          list.append(output.0, [
            json.object([
              #("kind", json.string("manager")),
              #("call", call),
            ]),
          ]),
          output.1,
        ))
      }
      moves.MoveInNotified(field, id) -> {
        use field <- result.try(field_id_json(field, context))
        use id <- result.try(atom_json(id, context))
        Ok(#(
          list.append(output.0, [
            json.object([
              #("kind", json.string("manager")),
              #(
                "call",
                json.object([
                  #("method", json.string("onMoveIn")),
                  #("field", field),
                  #("id", id),
                ]),
              ),
            ]),
          ]),
          output.1,
        ))
      }
      moves.KeyMoveNotified(field, key, count) -> {
        use call <- result.try(
          manager_range_json(0, "moveKey", field, key, count, context, []),
        )
        Ok(#(
          list.append(output.0, [
            json.object([
              #("kind", json.string("manager")),
              #("call", call),
            ]),
          ]),
          output.1,
        ))
      }
      moves.RangeRead(_, _, _, _, _, _)
      | moves.DependenciesInvalidated(_)
      | moves.GenericConverted(_, _, _, _) -> Ok(output)
    }
  })
  |> result.map(fn(output) { codec.array(output.0) })
}

fn read_evidence_json(trace: List(moves.TraceEvent)) -> Json {
  let evidence =
    list.fold(
      trace,
      #(False, False, False, False, False, False),
      fn(found, event) {
        case event {
          moves.RangeRead(_, _, count, dependency, present, length) -> #(
            found.0 || !present,
            found.1 || present,
            found.2 || length < count,
            found.3 || dependency,
            found.4,
            found.5,
          )
          moves.DependenciesInvalidated(_) -> #(
            found.0,
            found.1,
            found.2,
            found.3,
            True,
            found.5,
          )
          moves.HandlerCalled(operation, field) -> #(
            found.0,
            found.1,
            found.2,
            found.3,
            found.4,
            found.5
              || list.filter(trace, fn(candidate) {
              candidate == moves.HandlerCalled(operation, field)
            })
            |> list.length
            |> fn(count) { count > 1 },
          )
          _ -> found
        }
      },
    )
  json.object([
    #("absent", json.bool(evidence.0)),
    #("found", json.bool(evidence.1)),
    #("partial", json.bool(evidence.2)),
    #("dependency", json.bool(evidence.3)),
    #("invalidation", json.bool(evidence.4)),
    #("retry", json.bool(evidence.5)),
  ])
}

fn output_json(values: List(a), encode: fn(a) -> Json) -> Json {
  json.array(values, encode)
}

fn manager_range_json(
  _sequence: Int,
  method: String,
  field: moves.FieldId,
  key: moves.Key,
  count: Int,
  context: Context,
  extra: List(#(String, Json)),
) -> Result(Json, String) {
  let moves.Key(side, revision, local_id) = key
  use field <- result.try(field_id_json(field, context))
  use revision <- result.try(optional_revision_json(revision, context))
  Ok(
    json.object([
      #("method", json.string(method)),
      #("field", field),
      #(
        "target",
        json.string(case side {
          moves.Source -> "source"
          moves.Destination -> "destination"
        }),
      ),
      #("revision", revision),
      #("localId", json.int(local_id)),
      #("count", json.int(count)),
      ..extra
    ]),
  )
}

fn conversion_json(
  trace: List(moves.TraceEvent),
  context: Context,
) -> Result(Json, String) {
  let raw_calls =
    list.filter_map(trace, fn(event) {
      case event {
        moves.GenericConverted(_, direction, field, children) ->
          Ok(#(direction, field, children))
        _ -> Error(Nil)
      }
    })
  use calls <- result.try(
    list.try_map(raw_calls, fn(call) {
      let #(direction, field, children) = call
      use field <- result.try(field_id_json(field, context))
      use children <- result.try(
        list.try_map(children, fn(child) {
          use id <- result.try(atom_json(child.1, context))
          Ok(codec.array([json.int(child.0), id]))
        }),
      )
      Ok(
        json.object([
          #("direction", json.string(direction)),
          #("field", field),
          #("children", codec.array(children)),
        ]),
      )
    }),
  )
  Ok(
    json.object([
      #("directions", json.array(raw_calls, fn(call) { json.string(call.0) })),
      #("calls", codec.array(calls)),
    ]),
  )
}
