import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import watershed/canonical_json
import watershed/fluid_ids
import watershed/json_ot.{type JsonValue, VArray, VObject, VString}
import watershed/tree/change
import watershed/tree/change_fixture_codec as fixture_codec
import watershed/tree/codec
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/map_forest_fixture
import watershed/tree/optional_field
import watershed/tree/schema
import watershed/tree/types

const allocation_session = "00000000-0000-4000-b000-000000000000"

type NamedChange {
  NamedChange(
    id: String,
    revision: Option(fluid_ids.StableId),
    change: change.Changeset,
  )
}

type Execution {
  Execution(changes: List(NamedChange), observations: List(OperationResult))
}

type OperationResult {
  OperationResult(operation: String, observation: Json, final: Json)
}

pub fn run(input: Json) -> Result(Json, String) {
  use input <- result.try(fixture_codec.parse(input))
  use _ <- result.try(
    fixture_codec.exact(input, [
      "profile",
      "schema",
      "scenarios",
    ]),
  )
  use _ <- result.try(validate_profile(input))
  use raw_schema <- result.try(fixture_codec.field(
    input,
    "schema",
    fixture_codec.text,
  ))
  use stored <- result.try(schema.stored_from_string(raw_schema) |> native)
  use map_types <- result.try(map_types(raw_schema))
  use scenarios <- result.try(
    fixture_codec.field(input, "scenarios", fn(value) {
      fixture_codec.many(value, fn(scenario) {
        run_scenario(scenario, raw_schema, stored, map_types)
      })
    }),
  )
  Ok(json.object([#("observations", fixture_codec.array(scenarios))]))
}

fn validate_profile(input: JsonValue) -> Result(Nil, String) {
  fixture_codec.field(input, "profile", fn(profile) {
    use _ <- result.try(
      fixture_codec.exact(profile, [
        "modularChange",
        "optionalField",
        "genericField",
      ]),
    )
    use modular <- result.try(fixture_codec.field(
      profile,
      "modularChange",
      fixture_codec.integer,
    ))
    use optional <- result.try(fixture_codec.field(
      profile,
      "optionalField",
      fixture_codec.integer,
    ))
    use generic <- result.try(fixture_codec.field(
      profile,
      "genericField",
      fixture_codec.integer,
    ))
    case modular, optional, generic {
      5, 2, 1 -> Ok(Nil)
      _, _, _ -> Error("unsupported map algebra codec profile")
    }
  })
}

fn run_scenario(
  value: JsonValue,
  raw_schema: String,
  stored: schema.StoredSchema,
  map_types: List(String),
) -> Result(Json, String) {
  use _ <- result.try(
    fixture_codec.exact(value, [
      "id",
      "initial",
      "compressor",
      "changes",
      "algebra",
      "operations",
      "finalOperation",
    ]),
  )
  use id <- result.try(fixture_codec.field(value, "id", fixture_codec.text))
  use _ <- result.try(nonempty(id, "scenario id"))
  use #(compressor, view, identity_order, revisions) <- result.try(
    fixture_codec.field(value, "compressor", compressor),
  )
  use initial <- result.try(
    fixture_codec.field(value, "initial", fn(initial) {
      initial_forest(initial, raw_schema, stored, map_types, view)
    }),
  )
  use changes <- result.try(
    fixture_codec.field(value, "changes", fn(value) {
      fixture_codec.many(value, fn(value) {
        decode_change(value, compressor, identity_order)
      })
    }),
  )
  use _ <- result.try(unique_change_ids(changes))
  use operations <- result.try(
    fixture_codec.field(value, "operations", fn(value) {
      fixture_codec.many(value, fixture_codec.text)
    }),
  )
  use _ <- result.try(unique_strings(operations, "operation selector"))
  use algebra <- result.try(fixture_codec.field(
    value,
    "algebra",
    fixture_codec.items,
  ))
  use execution <- result.try(
    list.try_fold(algebra, Execution(changes, []), fn(state, operation) {
      run_operation(
        state,
        operation,
        operations,
        revisions,
        identity_order,
        initial,
      )
      |> result.map_error(fn(error) { id <> ": " <> error })
    }),
  )
  use final_operation <- result.try(fixture_codec.field(
    value,
    "finalOperation",
    fixture_codec.text,
  ))
  use final <- result.try(find_final(execution.observations, final_operation))
  use initial_observation <- result.try(observe(initial))
  use detached_identity <- result.try(detached_identity(id, execution.changes))
  let members = [
    #("id", json.string(id)),
    #("initial", initial_observation),
    #(
      "intermediate",
      execution.observations
        |> list.reverse
        |> list.map(fn(result) { result.observation })
        |> fixture_codec.array,
    ),
    #("final", final),
  ]
  let members = case detached_identity {
    None -> members
    Some(value) -> list.append(members, [#("detachedIdentity", value)])
  }
  Ok(json.object(members))
}

fn compressor(
  value: JsonValue,
) -> Result(
  #(
    fluid_ids.Compressor,
    fluid_ids.StableId,
    change.IdentityOrder,
    fixture_codec.Revisions,
  ),
  String,
) {
  use _ <- result.try(
    fixture_codec.exact(value, [
      "localSessionId",
      "revisions",
    ]),
  )
  use local_raw <- result.try(fixture_codec.field(
    value,
    "localSessionId",
    fixture_codec.text,
  ))
  use local <- result.try(
    fluid_ids.session_id(local_raw) |> result.map_error(string.inspect),
  )
  use revisions <- result.try(
    fixture_codec.field(value, "revisions", fn(value) {
      fixture_codec.many(value, fn(value) {
        use _ <- result.try(fixture_codec.exact(value, ["stable", "encoded"]))
        use stable <- result.try(fixture_codec.field(
          value,
          "stable",
          fixture_codec.revision,
        ))
        use encoded <- result.try(fixture_codec.field(
          value,
          "encoded",
          fixture_codec.integer,
        ))
        case encoded >= 0 {
          True -> Ok(#(stable, encoded))
          False -> Error("compressed revision must be nonnegative")
        }
      })
    }),
  )
  use first <- result.try(
    list.first(revisions)
    |> result.map_error(fn(_) { "scenario has no compressor revisions" }),
  )
  use revisions <- result.try(unique_revisions(revisions))
  let max_encoded =
    list.fold(revisions, 0, fn(maximum, entry) {
      case entry.1 > maximum {
        True -> entry.1
        False -> maximum
      }
    })
  use allocation <- result.try(
    fluid_ids.session_id(allocation_session)
    |> result.map_error(string.inspect),
  )
  use compressor <- result.try(
    fluid_ids.finalize(
      fluid_ids.new(local),
      fluid_ids.CreationRange(
        allocation,
        Some(fluid_ids.RangeIds(1, max_encoded + 1, max_encoded + 1, [])),
      ),
    )
    |> result.map_error(string.inspect),
  )
  use _ <- result.try(
    list.try_each(revisions, fn(entry) {
      use encoded <- result.try(
        fluid_ids.session_space_id(entry.1)
        |> result.map_error(string.inspect),
      )
      use decoded <- result.try(
        fluid_ids.decompress(compressor, encoded)
        |> result.map_error(string.inspect),
      )
      case decoded == entry.0 {
        True -> Ok(Nil)
        False -> Error("revision table does not match compressed identity")
      }
    }),
  )
  use identity_order <- result.try(
    codec.identity_order(
      list.map(revisions, fn(entry) { entry.0 }),
      compressor,
      "map algebra",
    )
    |> native,
  )
  Ok(#(compressor, first.0, identity_order, revisions))
}

fn unique_revisions(
  revisions: List(#(fluid_ids.StableId, Int)),
) -> Result(List(#(fluid_ids.StableId, Int)), String) {
  list.try_fold(
    revisions,
    [],
    fn(unique: List(#(fluid_ids.StableId, Int)), entry) {
      case
        list.find(unique, fn(current) {
          current.0 == entry.0 || current.1 == entry.1
        })
      {
        Error(Nil) -> Ok([entry, ..unique])
        Ok(current) if current == entry -> Ok(unique)
        Ok(_) -> Error("conflicting compressor revision entry")
      }
    },
  )
}

fn initial_forest(
  value: JsonValue,
  raw_schema: String,
  stored: schema.StoredSchema,
  map_types: List(String),
  view: fluid_ids.StableId,
) -> Result(forest.Forest, String) {
  use _ <- result.try(fixture_codec.exact(value, ["schema", "root"]))
  use scenario_schema <- result.try(fixture_codec.field(
    value,
    "schema",
    fixture_codec.text,
  ))
  use _ <- result.try(case scenario_schema == raw_schema {
    True -> Ok(Nil)
    False -> Error("scenario schema does not match fixture schema")
  })
  use root <- result.try(fixture_codec.field(value, "root", fixture_codec.tree))
  forest.new(view, stored, Some(normalize_maps(root, map_types))) |> native
}

fn decode_change(
  value: JsonValue,
  compressor: fluid_ids.Compressor,
  identity_order: change.IdentityOrder,
) -> Result(NamedChange, String) {
  use _ <- result.try(
    fixture_codec.exact(value, [
      "id",
      "revision",
      "encodingContext",
      "encoded",
    ]),
  )
  use id <- result.try(fixture_codec.field(value, "id", fixture_codec.text))
  use _ <- result.try(nonempty(id, "change id"))
  use revision <- result.try(
    fixture_codec.field(value, "revision", fn(value) {
      fixture_codec.optional(value, fixture_codec.revision)
    }),
  )
  use context <- result.try(
    fixture_codec.field(value, "encodingContext", fn(value) {
      decode_context(value, revision, compressor)
    }),
  )
  use encoded <- result.try(fixture_codec.get(value, "encoded"))
  let encoded_json = json_ot.to_json(encoded)
  use decoded <- result.try(
    codec.decode_modular(
      encoded_json,
      codec.DecodeContext(codec.Fluid310, compressor),
      context,
    )
    |> native,
  )
  use decoded <- result.try(
    change.with_identity_order(decoded, identity_order) |> native,
  )
  Ok(NamedChange(id, revision, decoded))
}

fn decode_context(
  value: JsonValue,
  change_revision: Option(fluid_ids.StableId),
  compressor: fluid_ids.Compressor,
) -> Result(codec.ChangeContext, String) {
  use _ <- result.try(
    fixture_codec.exact(value, [
      "originatorId",
      "revision",
      "encodedRevision",
      "isSummary",
    ]),
  )
  use originator_raw <- result.try(fixture_codec.field(
    value,
    "originatorId",
    fixture_codec.text,
  ))
  use originator <- result.try(
    fluid_ids.session_id(originator_raw) |> result.map_error(string.inspect),
  )
  use revision <- result.try(
    fixture_codec.field(value, "revision", fn(value) {
      fixture_codec.optional(value, fixture_codec.revision)
    }),
  )
  use encoded <- result.try(
    fixture_codec.field(value, "encodedRevision", fn(value) {
      fixture_codec.optional(value, fixture_codec.integer)
    }),
  )
  use summary <- result.try(fixture_codec.field(
    value,
    "isSummary",
    fixture_codec.boolean,
  ))
  use _ <- result.try(case revision == change_revision {
    True -> Ok(Nil)
    False -> Error("change revision does not match encoding context")
  })
  use _ <- result.try(validate_encoded_revision(revision, encoded, compressor))
  let purpose = case summary {
    True -> codec.Summary
    False -> codec.Message
  }
  Ok(codec.ChangeContext(originator, revision, purpose))
}

fn validate_encoded_revision(
  revision: Option(fluid_ids.StableId),
  encoded: Option(Int),
  compressor: fluid_ids.Compressor,
) -> Result(Nil, String) {
  case revision, encoded {
    None, None -> Ok(Nil)
    Some(revision), Some(encoded) -> {
      use encoded <- result.try(
        fluid_ids.session_space_id(encoded) |> result.map_error(string.inspect),
      )
      use decoded <- result.try(
        fluid_ids.decompress(compressor, encoded)
        |> result.map_error(string.inspect),
      )
      case decoded == revision {
        True -> Ok(Nil)
        False -> Error("encoded revision does not match stable revision")
      }
    }
    _, _ -> Error("revision and encoded revision must both be present")
  }
}

fn run_operation(
  state: Execution,
  operation: JsonValue,
  operations: List(String),
  revisions: fixture_codec.Revisions,
  identity_order: change.IdentityOrder,
  initial: forest.Forest,
) -> Result(Execution, String) {
  use selector <- result.try(fixture_codec.field(
    operation,
    "operation",
    fixture_codec.text,
  ))
  use _ <- result.try(case list.contains(operations, selector) {
    True -> Ok(Nil)
    False -> Error("unsupported map algebra operation: " <> selector)
  })
  use output_id <- result.try(fixture_codec.field(
    operation,
    "output",
    fixture_codec.text,
  ))
  use output <- result.try(find_change(state.changes, output_id))
  use #(computed, checkpoints, starting_watermark) <- result.try(case selector {
    "compose" ->
      compose(operation, state.changes)
      |> result.map(fn(output) { #(output.0, output.1, None) })
    "invert" -> invert(operation, state.changes)
    "rebase-left-over-right" | "rebase-right-over-left" ->
      rebase(operation, state.changes)
      |> result.map(fn(output) { #(output.0, output.1, None) })
    _ -> Error("unsupported map algebra operation: " <> selector)
  })
  use computed <- result.try(case selector {
    "invert" ->
      case starting_watermark {
        Some(watermark) ->
          normalize_inverse(
            computed,
            output.revision,
            identity_order,
            watermark,
          )
        None -> Error("invert normalization has no starting watermark")
      }
    _ -> Ok(computed)
  })
  let computed_output = NamedChange(..output, change: computed)
  let changes = replace_change(state.changes, computed_output)
  use encoded <- result.try(fixture_codec.wire_tagged(
    computed,
    revisions,
    output.revision,
  ))
  use #(checkpoint_observations, final) <- result.try(run_checkpoints(
    initial,
    changes,
    checkpoints,
  ))
  let observation =
    json.object([
      #("operation", json.string(selector)),
      #("encoded", encoded),
      #("checkpoints", fixture_codec.array(checkpoint_observations)),
      #("final", final),
    ])
  Ok(
    Execution(changes, [
      OperationResult(selector, observation, final),
      ..state.observations
    ]),
  )
}

fn compose(
  value: JsonValue,
  changes: List(NamedChange),
) -> Result(#(change.Changeset, List(String)), String) {
  use _ <- result.try(
    fixture_codec.exact(value, [
      "operation",
      "changes",
      "output",
    ]),
  )
  use operands <- result.try(
    fixture_codec.field(value, "changes", fn(value) {
      fixture_codec.many(value, fn(value) {
        use id <- result.try(fixture_codec.text(value))
        find_change(changes, id)
      })
    }),
  )
  use composed <- result.try(
    change.compose(list.map(operands, tagged)) |> native,
  )
  use output <- result.try(fixture_codec.field(
    value,
    "output",
    fixture_codec.text,
  ))
  Ok(#(composed, [output]))
}

fn invert(
  value: JsonValue,
  changes: List(NamedChange),
) -> Result(#(change.Changeset, List(String), Option(Int)), String) {
  use _ <- result.try(
    fixture_codec.exact(value, [
      "operation",
      "change",
      "inverseRevision",
      "output",
    ]),
  )
  use original_id <- result.try(fixture_codec.field(
    value,
    "change",
    fixture_codec.text,
  ))
  use original <- result.try(find_change(changes, original_id))
  use inverse <- result.try(fixture_codec.field(
    value,
    "inverseRevision",
    fixture_codec.revision,
  ))
  use output <- result.try(fixture_codec.field(
    value,
    "output",
    fixture_codec.text,
  ))
  use output_change <- result.try(find_change(changes, output))
  use _ <- result.try(case output_change.revision == Some(inverse) {
    True -> Ok(Nil)
    False -> Error("inverse revision does not match output revision")
  })
  use starting_watermark <- result.try(inversion_starting_watermark(
    original,
    inverse,
  ))
  use inverted <- result.try(
    change.invert(tagged(original), False, inverse) |> native,
  )
  Ok(#(inverted, [original_id, output], Some(starting_watermark)))
}

fn rebase(
  value: JsonValue,
  changes: List(NamedChange),
) -> Result(#(change.Changeset, List(String)), String) {
  use _ <- result.try(
    fixture_codec.exact(value, [
      "operation",
      "change",
      "over",
      "revisionMetadata",
      "output",
    ]),
  )
  use original <- result.try(change_operand(value, "change", changes))
  use over_id <- result.try(fixture_codec.field(
    value,
    "over",
    fixture_codec.text,
  ))
  use over <- result.try(find_change(changes, over_id))
  use metadata <- result.try(
    fixture_codec.field(value, "revisionMetadata", fn(value) {
      fixture_codec.many(value, revision_metadata)
    }),
  )
  use context <- result.try(change.rebase_context(metadata) |> native)
  use rebased <- result.try(
    change.rebase(tagged(original), tagged(over), context) |> native,
  )
  use output <- result.try(fixture_codec.field(
    value,
    "output",
    fixture_codec.text,
  ))
  Ok(#(rebased, [over_id, output]))
}

fn change_operand(
  value: JsonValue,
  key: String,
  changes: List(NamedChange),
) -> Result(NamedChange, String) {
  use id <- result.try(fixture_codec.field(value, key, fixture_codec.text))
  find_change(changes, id)
}

fn revision_metadata(value: JsonValue) -> Result(change.RevisionInfo, String) {
  let keys = case value {
    VObject(fields) ->
      case list.key_find(fields, "rollbackOf") {
        Ok(_) -> ["revision", "rollbackOf"]
        Error(_) -> ["revision"]
      }
    _ -> ["revision"]
  }
  use _ <- result.try(fixture_codec.exact(value, keys))
  use revision <- result.try(fixture_codec.field(
    value,
    "revision",
    fixture_codec.revision,
  ))
  use rollback <- result.try(case list.contains(keys, "rollbackOf") {
    False -> Ok(None)
    True ->
      fixture_codec.field(value, "rollbackOf", fn(value) {
        fixture_codec.optional(value, fixture_codec.revision)
      })
  })
  Ok(change.RevisionInfo(revision, rollback))
}

fn tagged(value: NamedChange) -> change.TaggedChange {
  change.TaggedChange(value.revision, None, value.change)
}

fn find_change(
  changes: List(NamedChange),
  id: String,
) -> Result(NamedChange, String) {
  list.find(changes, fn(change) { change.id == id })
  |> result.map_error(fn(_) { "unknown map change: " <> id })
}

fn replace_change(
  changes: List(NamedChange),
  replacement: NamedChange,
) -> List(NamedChange) {
  list.map(changes, fn(change) {
    case change.id == replacement.id {
      True -> replacement
      False -> change
    }
  })
}

fn inversion_starting_watermark(
  original: NamedChange,
  inverse_revision: fluid_ids.StableId,
) -> Result(Int, String) {
  let data = change.to_data(original.change)
  let revision_is_used =
    original.revision == Some(inverse_revision)
    || list.any(data.revisions, fn(info) {
      info.revision == inverse_revision
      || info.rollback_of == Some(inverse_revision)
    })
    || list.any(change_atoms(data), fn(id) {
      id.revision == Some(inverse_revision)
    })
  use _ <- result.try(case revision_is_used {
    True -> Error("inverse revision is not fresh")
    False -> Ok(Nil)
  })
  let revisions = case data.revisions {
    [] ->
      case original.revision {
        None -> []
        Some(revision) -> [revision]
      }
    revisions -> list.map(revisions, fn(info) { info.revision })
  }
  let rollback_revisions =
    data.revisions
    |> list.fold([], fn(revisions, info) {
      case info.rollback_of {
        None -> revisions
        Some(revision) -> [revision, ..revisions]
      }
    })
  let revision_count =
    list.append(revisions, rollback_revisions)
    |> list.unique
    |> list.length
  Ok(reserved_watermark(data.max_local_id, revision_count))
}

fn reserved_watermark(max_local_id: Int, revision_count: Int) -> Int {
  case max_local_id, revision_count {
    -1, _ -> -1
    _, 0 -> max_local_id
    _, _ -> reserve_ranges(max_local_id, revision_count, -1)
  }
}

fn reserve_ranges(original_max: Int, count: Int, watermark: Int) -> Int {
  case count {
    0 -> watermark
    _ if watermark == -1 -> reserve_ranges(original_max, count - 1, original_max)
    _ -> reserve_ranges(original_max, count - 1, watermark + original_max + 1)
  }
}

fn normalize_inverse(
  value: change.Changeset,
  revision: Option(fluid_ids.StableId),
  identity_order: change.IdentityOrder,
  starting_watermark: Int,
) -> Result(change.Changeset, String) {
  // Fresh inverse identifiers have no semantic identity.
  // Normalize them by detached application order.
  case revision {
    None -> Ok(value)
    Some(revision) -> {
      use delta <- result.try(
        change.into_delta(change.TaggedChange(Some(revision), None, value))
        |> native,
      )
      let detach_ids =
        forest.delta_data(delta)
        |> inverse_detaches
        |> list.filter(fn(id) {
          id.revision == Some(revision) && id.local_id > starting_watermark
        })
        |> list.unique
      let all_ids =
        change.to_data(value)
        |> change_atoms
        |> list.filter(fn(id) {
          id.revision == Some(revision) && id.local_id > starting_watermark
        })
        |> list.unique
        |> list.sort(fn(left, right) {
          int.compare(left.local_id, right.local_id)
        })
      let ids =
        list.append(
          detach_ids,
          list.filter(all_ids, fn(id) { !list.contains(detach_ids, id) }),
        )
      let local_ids =
        all_ids
        |> list.map(fn(id) { id.local_id })
      let mappings =
        list.zip(ids, local_ids)
        |> list.map(fn(entry) {
          #(entry.0, types.AtomId(..entry.0, local_id: entry.1))
        })
      let data = change.to_data(value)
      change.from_data(
        change.ChangeData(
          ..data,
          fields: normalize_fields(data.fields, mappings),
          nodes: list.map(data.nodes, fn(entry) {
            #(
              normalize_atom(entry.0, mappings),
              change.NodeChange(normalize_fields(entry.1.fields, mappings)),
            )
          }),
          parents: list.map(data.parents, fn(entry) {
            let change.ParentField(parent, field) = entry.1
            #(
              normalize_atom(entry.0, mappings),
              change.ParentField(
                option.map(parent, fn(id) { normalize_atom(id, mappings) }),
                field,
              ),
            )
          }),
          aliases: list.map(data.aliases, fn(entry) {
            #(
              normalize_atom(entry.0, mappings),
              normalize_atom(entry.1, mappings),
            )
          }),
          builds: list.map(data.builds, fn(build) {
            forest.Build(normalize_atom(build.id, mappings), build.trees)
          }),
          destroys: list.map(data.destroys, fn(destroy) {
            forest.Destroy(normalize_atom(destroy.id, mappings), destroy.count)
          }),
          refreshers: list.map(data.refreshers, fn(build) {
            forest.Build(normalize_atom(build.id, mappings), build.trees)
          }),
        ),
        identity_order,
      )
      |> native
    }
  }
}

fn change_atoms(data: change.ChangeData) -> List(types.AtomId) {
  list.flatten([
    fields_atoms(data.fields),
    list.flat_map(data.nodes, fn(entry) {
      [entry.0, ..fields_atoms(entry.1.fields)]
    }),
    list.flat_map(data.parents, fn(entry) {
      let change.ParentField(parent, _) = entry.1
      case parent {
        None -> [entry.0]
        Some(parent) -> [entry.0, parent]
      }
    }),
    list.flat_map(data.aliases, fn(entry) { [entry.0, entry.1] }),
    list.map(data.builds, fn(build) { build.id }),
    list.map(data.destroys, fn(destroy) { destroy.id }),
    list.map(data.refreshers, fn(build) { build.id }),
  ])
}

fn fields_atoms(
  fields: List(#(String, change.FieldChange)),
) -> List(types.AtomId) {
  list.flat_map(fields, fn(entry) {
    case entry.1 {
      change.GenericField(children) -> list.map(children, fn(child) { child.1 })
      change.ValueField(field) | change.OptionalField(field) ->
        optional_atoms(field)
    }
  })
}

fn optional_atoms(field: optional_field.FieldChange) -> List(types.AtomId) {
  let moves = list.flat_map(field.moves, fn(move) { [move.0, move.1] })
  let children =
    list.flat_map(field.child_changes, fn(child) {
      case child.0 {
        optional_field.Active -> [child.1]
        optional_field.Detached(id) -> [id, child.1]
      }
    })
  let replacement = case field.replacement {
    None -> []
    Some(replacement) -> {
      let source = case replacement.source {
        Some(optional_field.Detached(id)) -> [id]
        _ -> []
      }
      [replacement.detach_id, ..source]
    }
  }
  list.flatten([moves, children, replacement])
}

fn inverse_detaches(data: forest.DeltaData) -> List(types.AtomId) {
  list.append(
    list.flat_map(data.global, fn(change) {
      delta_field_detaches(change.fields)
    }),
    delta_field_detaches(data.fields),
  )
}

fn delta_field_detaches(
  fields: List(#(String, forest.FieldDelta)),
) -> List(types.AtomId) {
  list.flat_map(fields, fn(field) {
    list.flat_map(field.1.marks, fn(mark) {
      let nested = delta_field_detaches(mark.fields)
      case mark.detach {
        None -> nested
        Some(id) -> list.append(nested, [id])
      }
    })
  })
}

fn normalize_fields(
  fields: List(#(String, change.FieldChange)),
  mappings: List(#(types.AtomId, types.AtomId)),
) -> List(#(String, change.FieldChange)) {
  list.map(fields, fn(entry) { #(entry.0, normalize_field(entry.1, mappings)) })
}

fn normalize_field(
  field: change.FieldChange,
  mappings: List(#(types.AtomId, types.AtomId)),
) -> change.FieldChange {
  case field {
    change.GenericField(children) ->
      change.GenericField(
        list.map(children, fn(child) {
          #(child.0, normalize_atom(child.1, mappings))
        }),
      )
    change.ValueField(field) ->
      change.ValueField(normalize_optional(field, mappings))
    change.OptionalField(field) ->
      change.OptionalField(normalize_optional(field, mappings))
  }
}

fn normalize_optional(
  field: optional_field.FieldChange,
  mappings: List(#(types.AtomId, types.AtomId)),
) -> optional_field.FieldChange {
  optional_field.FieldChange(
    list.map(field.moves, fn(move) {
      #(normalize_atom(move.0, mappings), normalize_atom(move.1, mappings))
    }),
    list.map(field.child_changes, fn(child) {
      #(
        normalize_register(child.0, mappings),
        normalize_atom(child.1, mappings),
      )
    }),
    option.map(field.replacement, fn(replacement) {
      optional_field.Replacement(
        replacement.was_empty,
        option.map(replacement.source, fn(source) {
          normalize_register(source, mappings)
        }),
        normalize_atom(replacement.detach_id, mappings),
      )
    }),
  )
}

fn normalize_register(
  register: optional_field.RegisterId,
  mappings: List(#(types.AtomId, types.AtomId)),
) -> optional_field.RegisterId {
  case register {
    optional_field.Active -> optional_field.Active
    optional_field.Detached(id) ->
      optional_field.Detached(normalize_atom(id, mappings))
  }
}

fn normalize_atom(
  id: types.AtomId,
  mappings: List(#(types.AtomId, types.AtomId)),
) -> types.AtomId {
  list.key_find(mappings, id) |> result.unwrap(id)
}

fn run_checkpoints(
  initial: forest.Forest,
  changes: List(NamedChange),
  ids: List(String),
) -> Result(#(List(Json), Json), String) {
  use initial_observation <- result.try(observe(initial))
  use #(state, observations) <- result.try(
    list.try_fold(
      ids,
      #(initial, [
        json.object([
          #("id", json.string("initial")),
          #("visible", initial_observation),
        ]),
      ]),
      fn(state, id) {
        use current <- result.try(find_change(changes, id))
        use delta <- result.try(change.into_delta(tagged(current)) |> native)
        use updated <- result.try(forest.apply_delta(state.0, delta) |> native)
        use visible <- result.try(observe(updated))
        Ok(#(
          updated,
          list.append(state.1, [
            json.object([
              #("id", json.string(id)),
              #("visible", visible),
            ]),
          ]),
        ))
      },
    ),
  )
  use final <- result.try(observe(state))
  Ok(#(observations, final))
}

fn observe(state: forest.Forest) -> Result(Json, String) {
  use visible <- result.try(
    map_forest_fixture.observe_field(state, ["items"]) |> native,
  )
  use visible <- result.try(fixture_codec.parse(visible))
  use entries <- result.try(fixture_codec.get(visible, "entries"))
  use data <- result.try(forest.export_data(state) |> native)
  let detached =
    data.detached
    |> list.map(fn(entry) {
      json.object([
        #("id", fixture_codec.atom_json(entry.id)),
        #("forestRootId", json.int(entry.forest_root_id)),
        #(
          "latestRelevantRevision",
          fixture_codec.nullable(
            entry.latest_relevant_revision,
            fixture_codec.revision_json,
          ),
        ),
        #("value", observation_tree_to_json(entry.value)),
      ])
    })
    |> list.sort(fn(left, right) {
      canonical_json.compare(json.to_string(left), json.to_string(right))
    })
  Ok(
    json.object([
      #("entries", normalize_observation_value(entries)),
      #("detached", fixture_codec.array(detached)),
    ]),
  )
}

fn normalize_observation_value(value: JsonValue) -> Json {
  case value {
    VArray(values) ->
      values |> list.map(normalize_observation_value) |> fixture_codec.array
    VObject(fields) ->
      case list.key_find(fields, "kind") {
        Ok(VString("map")) -> {
          let assert Ok(VString(identifier)) = list.key_find(fields, "schemaId")
          let assert Ok(entries) = list.key_find(fields, "entries")
          json.object([
            #("kind", json.string("object")),
            #("type", json.string(identifier)),
            #("fields", normalize_observation_value(entries)),
          ])
        }
        _ ->
          json.object(
            list.map(fields, fn(field) {
              #(field.0, normalize_observation_value(field.1))
            }),
          )
      }
    other -> json_ot.to_json(other)
  }
}

fn observation_tree_to_json(value: types.TreeValue) -> Json {
  case value {
    types.MapValue(identifier, entries) ->
      json.object([
        #("kind", json.string("object")),
        #("type", json.string(identifier)),
        #(
          "fields",
          json.array(entries, fn(entry) {
            fixture_codec.array([
              json.string(entry.0),
              observation_tree_to_json(entry.1),
            ])
          }),
        ),
      ])
    types.ObjectValue(identifier, fields) ->
      json.object([
        #("kind", json.string("object")),
        #("type", json.string(identifier)),
        #(
          "fields",
          json.array(fields, fn(field) {
            fixture_codec.array([
              json.string(field.0),
              observation_tree_to_json(field.1),
            ])
          }),
        ),
      ])
    other -> fixtures.tree_value_to_json(other)
  }
}

fn find_final(
  observations: List(OperationResult),
  selector: String,
) -> Result(Json, String) {
  let matching =
    list.filter(observations, fn(result) { result.operation == selector })
  case matching {
    [result] -> Ok(result.final)
    [] -> Error("final operation was not executed: " <> selector)
    _ -> Error("final operation is repeated: " <> selector)
  }
}

fn detached_identity(
  scenario: String,
  changes: List(NamedChange),
) -> Result(Option(Json), String) {
  case scenario {
    "nested-edit-vs-replace" | "nested-edit-vs-delete" -> {
      use left <- result.try(find_change(changes, "left"))
      use right <- result.try(find_change(changes, "right"))
      let detached = types.AtomId(right.revision, 0)
      let node = types.AtomId(left.revision, 0)
      Ok(Some(json.array([detached, node], fixture_codec.atom_json)))
    }
    _ -> Ok(None)
  }
}

fn map_types(raw_schema: String) -> Result(List(String), String) {
  use value <- result.try(
    json_ot.parse_json(raw_schema) |> result.map_error(string.inspect),
  )
  use nodes <- result.try(fixture_codec.get(value, "nodes"))
  case nodes {
    VObject(definitions) ->
      Ok(
        list.filter_map(definitions, fn(definition) {
          case fixture_codec.get(definition.1, "kind") {
            Ok(VObject(kinds)) ->
              case list.key_find(kinds, "map") {
                Ok(_) -> Ok(definition.0)
                Error(_) -> Error(Nil)
              }
            _ -> Error(Nil)
          }
        }),
      )
    _ -> Error("schema nodes must be an object")
  }
}

fn normalize_maps(
  value: types.TreeValue,
  map_types: List(String),
) -> types.TreeValue {
  case value {
    types.ObjectValue(identifier, fields) -> {
      let fields =
        list.map(fields, fn(field) {
          #(field.0, normalize_maps(field.1, map_types))
        })
      case list.contains(map_types, identifier) {
        True -> types.MapValue(identifier, fields)
        False -> types.ObjectValue(identifier, fields)
      }
    }
    types.MapValue(identifier, entries) ->
      types.MapValue(
        identifier,
        list.map(entries, fn(entry) {
          #(entry.0, normalize_maps(entry.1, map_types))
        }),
      )
    other -> other
  }
}

fn unique_change_ids(changes: List(NamedChange)) -> Result(Nil, String) {
  unique_strings(
    list.map(changes, fn(change) { change.id }),
    "change identifier",
  )
}

fn unique_strings(values: List(String), name: String) -> Result(Nil, String) {
  case list.length(list.unique(values)) == list.length(values) {
    True -> Ok(Nil)
    False -> Error("repeated " <> name)
  }
}

fn nonempty(value: String, name: String) -> Result(Nil, String) {
  case value == "" {
    True -> Error(name <> " must not be empty")
    False -> Ok(Nil)
  }
}

fn native(value: Result(a, error)) -> Result(a, String) {
  value |> result.map_error(string.inspect)
}
