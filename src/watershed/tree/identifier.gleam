//// Identifier defaults for newly authored tree content.

import gleam/list
import gleam/result
import gleam/string
import watershed/fluid_ids
import watershed/tree/schema
import watershed/tree/types

pub fn materialize_value(
  stored: schema.StoredSchema,
  value: types.TreeValue,
  compressor: fluid_ids.Compressor,
) -> Result(#(types.TreeValue, fluid_ids.Compressor), types.TreeError) {
  use #(value, compressor) <- result.try(materialize(stored, value, compressor))
  use _ <- result.try(schema.validate_subtree(stored, value))
  Ok(#(value, compressor))
}

pub fn materialize_edit(
  stored: schema.StoredSchema,
  edit: types.Edit,
  compressor: fluid_ids.Compressor,
) -> Result(#(types.Edit, fluid_ids.Compressor), types.TreeError) {
  case edit {
    types.SetField(path, value) -> {
      use #(value, compressor) <- result.try(materialize_value(
        stored,
        value,
        compressor,
      ))
      Ok(#(types.SetField(path, value), compressor))
    }
    types.MapSet(path, key, value) -> {
      use #(value, compressor) <- result.try(materialize_value(
        stored,
        value,
        compressor,
      ))
      Ok(#(types.MapSet(path, key, value), compressor))
    }
    types.ArrayInsert(path, index, values) -> {
      use #(values, compressor) <- result.try(materialize_inserted_values(
        stored,
        values,
        [],
        compressor,
      ))
      Ok(#(types.ArrayInsert(path, index, values), compressor))
    }
    types.ClearField(_)
    | types.MapDelete(_, _)
    | types.ArrayRemove(_, _, _)
    | types.ArrayMove(_, _, _, _, _) -> Ok(#(edit, compressor))
  }
}

fn materialize_inserted_values(
  stored: schema.StoredSchema,
  remaining: List(types.TreeValue),
  output: List(types.TreeValue),
  compressor: fluid_ids.Compressor,
) -> Result(#(List(types.TreeValue), fluid_ids.Compressor), types.TreeError) {
  case remaining {
    [] -> Ok(#(list.reverse(output), compressor))
    [value, ..rest] -> {
      use #(value, compressor) <- result.try(materialize(
        stored,
        value,
        compressor,
      ))
      materialize_inserted_values(stored, rest, [value, ..output], compressor)
    }
  }
}

fn materialize(
  stored: schema.StoredSchema,
  value: types.TreeValue,
  compressor: fluid_ids.Compressor,
) -> Result(#(types.TreeValue, fluid_ids.Compressor), types.TreeError) {
  case value {
    types.ObjectValue(type_id, fields) -> {
      use node <- result.try(schema.node_schema(stored, type_id))
      case node {
        schema.Object(definitions) -> {
          use #(fields, compressor) <- result.try(materialize_identifiers(
            definitions,
            fields,
            compressor,
          ))
          use #(fields, compressor) <- result.try(materialize_fields(
            stored,
            list.reverse(fields),
            [],
            compressor,
          ))
          Ok(#(types.ObjectValue(type_id, fields), compressor))
        }
        _ -> Ok(#(value, compressor))
      }
    }
    types.MapValue(type_id, entries) -> {
      use #(entries, compressor) <- result.try(materialize_fields(
        stored,
        list.reverse(entries),
        [],
        compressor,
      ))
      Ok(#(types.MapValue(type_id, entries), compressor))
    }
    types.ArrayValue(type_id, elements) -> {
      use #(elements, compressor) <- result.try(materialize_values(
        stored,
        list.reverse(elements),
        [],
        compressor,
      ))
      Ok(#(types.ArrayValue(type_id, elements), compressor))
    }
    types.StringValue(_)
    | types.NumberValue(_)
    | types.BooleanValue(_)
    | types.NullValue -> Ok(#(value, compressor))
  }
}

fn materialize_identifiers(
  definitions: List(#(String, schema.FieldSchema)),
  fields: List(#(String, types.TreeValue)),
  compressor: fluid_ids.Compressor,
) -> Result(
  #(List(#(String, types.TreeValue)), fluid_ids.Compressor),
  types.TreeError,
) {
  definitions
  |> list.try_fold(#(fields, compressor), fn(state, definition) {
    let schema.FieldSchema(cardinality, _) = definition.1
    case cardinality, list.key_find(state.0, definition.0) {
      schema.Identifier, Error(Nil) -> {
        use #(compressor, local) <- result.try(
          fluid_ids.generate(state.1)
          |> result.map_error(fn(error) {
            types.CorruptData(
              "tree identifier allocation",
              string.inspect(error),
            )
          }),
        )
        use stable <- result.try(
          fluid_ids.decompress(compressor, local)
          |> result.map_error(fn(error) {
            types.CorruptData(
              "tree identifier allocation",
              string.inspect(error),
            )
          }),
        )
        Ok(#(
          list.append(state.0, [
            #(
              definition.0,
              types.StringValue(fluid_ids.stable_id_to_string(stable)),
            ),
          ]),
          compressor,
        ))
      }
      _, _ -> Ok(state)
    }
  })
}

fn materialize_fields(
  stored: schema.StoredSchema,
  remaining: List(#(String, types.TreeValue)),
  output: List(#(String, types.TreeValue)),
  compressor: fluid_ids.Compressor,
) -> Result(
  #(List(#(String, types.TreeValue)), fluid_ids.Compressor),
  types.TreeError,
) {
  case remaining {
    [] -> Ok(#(output, compressor))
    [field, ..rest] -> {
      use #(value, compressor) <- result.try(materialize(
        stored,
        field.1,
        compressor,
      ))
      materialize_fields(
        stored,
        rest,
        [#(field.0, value), ..output],
        compressor,
      )
    }
  }
}

fn materialize_values(
  stored: schema.StoredSchema,
  remaining: List(types.TreeValue),
  output: List(types.TreeValue),
  compressor: fluid_ids.Compressor,
) -> Result(#(List(types.TreeValue), fluid_ids.Compressor), types.TreeError) {
  case remaining {
    [] -> Ok(#(output, compressor))
    [value, ..rest] -> {
      use #(value, compressor) <- result.try(materialize(
        stored,
        value,
        compressor,
      ))
      materialize_values(stored, rest, [value, ..output], compressor)
    }
  }
}
