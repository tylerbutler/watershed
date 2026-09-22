import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/fluid_ids.{type StableId}
import watershed/json_ot.{type JsonValue, VObject}
import watershed/tree/change
import watershed/tree/change_fixture_codec as codec
import watershed/tree/fixtures
import watershed/tree/forest
import watershed/tree/forest_fixture
import watershed/tree/schema
import watershed/tree/types

type Changes =
  List(#(String, change.TaggedChange))

type Execution {
  Execution(changes: Changes, ids: List(String), observations: List(Json))
}

type Evaluation {
  Evaluation(change: Option(change.TaggedChange), extra: List(#(String, Json)))
}

pub fn run(input: Json) -> Result(Json, String) {
  use input <- result.try(codec.parse(input))
  use _ <- result.try(
    codec.exact(input, [
      "compiler", "codecs", "compression", "oldestCompatibleClient", "changes",
      "revisions", "operations", "expanded",
    ]),
  )
  use _ <- result.try(validate_profile(input))
  use expanded <- result.try(codec.get(input, "expanded"))
  use _ <- result.try(
    codec.exact(expanded, [
      "changes", "tags", "revisions", "operations", "scenarios",
    ]),
  )
  use revisions <- result.try(
    codec.field(expanded, "revisions", fn(value) {
      codec.many(value, fn(entry) {
        use _ <- result.try(codec.exact(entry, ["encoded", "stable"]))
        use stable <- result.try(codec.field(entry, "stable", codec.revision))
        use encoded <- result.try(codec.field(entry, "encoded", codec.integer))
        case encoded >= 0 && encoded <= 9_007_199_254_740_991 {
          True -> Ok(#(stable, encoded))
          False -> Error("invalid compressed revision")
        }
      })
    }),
  )
  use _ <- result.try(unique(list.map(revisions, fn(entry) { entry.0 })))
  use _ <- result.try(unique(list.map(revisions, fn(entry) { entry.1 })))
  use identity_order <- result.try(
    change.identity_order(revisions) |> codec.native,
  )
  use changes <- result.try(initial_changes(
    input,
    expanded,
    revisions,
    identity_order,
  ))
  use original <- result.try(original_observations(input, changes, revisions))
  use operations <- result.try(codec.field(expanded, "operations", codec.items))
  use execution <- result.try(
    list.try_fold(
      operations,
      Execution(changes, list.map(changes, fn(entry) { entry.0 }), []),
      fn(state, operation) {
        run_operation(state, operation, revisions, identity_order)
      },
    ),
  )
  use scenarios <- result.try(codec.field(expanded, "scenarios", codec.items))
  use forest <- result.try(run_forests(scenarios, execution.changes))
  Ok(
    json.object([
      #(
        "observations",
        codec.array(list.append(
          original,
          list.append(list.reverse(execution.observations), forest),
        )),
      ),
    ]),
  )
}

fn validate_profile(input: JsonValue) -> Result(Nil, String) {
  use compiler <- result.try(codec.field(input, "compiler", codec.text))
  use oldest <- result.try(codec.field(
    input,
    "oldestCompatibleClient",
    codec.text,
  ))
  use compression <- result.try(codec.field(input, "compression", codec.integer))
  use codecs <- result.try(codec.get(input, "codecs"))
  use _ <- result.try(codec.exact(codecs, ["modular", "optional", "required"]))
  use modular <- result.try(codec.field(codecs, "modular", codec.integer))
  use optional <- result.try(codec.field(codecs, "optional", codec.integer))
  use required <- result.try(codec.field(codecs, "required", codec.integer))
  case compiler, oldest, compression, modular, optional, required {
    "2.117.0", "2.117.0", 0, 5, 2, 2 -> Ok(Nil)
    _, _, _, _, _, _ -> Error("unsupported modular fixture codec profile")
  }
}

fn unique(values: List(a)) -> Result(Nil, String) {
  case list.length(list.unique(values)) == list.length(values) {
    True -> Ok(Nil)
    False -> Error("duplicate fixture identifier")
  }
}

fn initial_changes(
  input: JsonValue,
  expanded: JsonValue,
  revisions: codec.Revisions,
  identity_order: change.IdentityOrder,
) -> Result(Changes, String) {
  use definitions <- result.try(codec.get(expanded, "changes"))
  use tags <- result.try(codec.get(expanded, "tags"))
  use encoded <- result.try(codec.get(input, "changes"))
  use original_revisions <- result.try(codec.get(input, "revisions"))
  let names = ["first", "second", "nested-detached"]
  use _ <- result.try(codec.exact(definitions, names))
  use _ <- result.try(codec.exact(tags, names))
  use _ <- result.try(codec.exact(encoded, ["first", "second"]))
  use _ <- result.try(
    codec.exact(original_revisions, ["first", "second", "replacement"]),
  )
  use _ <- result.try(
    codec.field(original_revisions, "replacement", fn(value) {
      decoded_revision(value, revisions)
    }),
  )
  use changes <- result.try(
    list.try_map(names, fn(name) {
      use value <- result.try(
        codec.field(definitions, name, fn(value) {
          codec.state(value, identity_order)
        }),
      )
      use tag <- result.try(codec.field(tags, name, codec.revision))
      use _ <- result.try(codec.wire_revision(tag, revisions))
      Ok(#(name, change.TaggedChange(Some(tag), None, value)))
    }),
  )
  use _ <- result.try(
    list.try_map(["first", "second"], fn(name) {
      use tagged <- result.try(find(changes, name))
      use original_tag <- result.try(
        codec.field(original_revisions, name, fn(value) {
          decoded_revision(value, revisions)
        }),
      )
      use _ <- result.try(case tagged.revision == Some(original_tag) {
        True -> Ok(Nil)
        False -> Error("inconsistent original and expanded revision context")
      })
      use actual <- result.try(codec.wire(tagged.change, revisions))
      use original <- result.try(codec.get(encoded, name))
      fixtures.first_difference(actual, json_ot.to_json(original))
      |> result.map_error(fn(path) {
        "encoded and structural input disagree: " <> name <> path
      })
    }),
  )
  Ok(changes)
}

fn decoded_revision(
  value: JsonValue,
  revisions: codec.Revisions,
) -> Result(StableId, String) {
  use encoded <- result.try(codec.integer(value))
  use pair <- result.try(
    list.find(revisions, fn(entry) { entry.1 == encoded })
    |> result.map_error(fn(_) { "unknown compressed revision" }),
  )
  Ok(pair.0)
}

fn find(changes: Changes, name: String) -> Result(change.TaggedChange, String) {
  list.key_find(changes, name)
  |> result.map_error(fn(_) { "unknown modular change: " <> name })
}

fn operand(
  value: JsonValue,
  key: String,
  changes: Changes,
) -> Result(change.TaggedChange, String) {
  use name <- result.try(codec.field(value, key, codec.text))
  find(changes, name)
}

fn retag(
  value: change.Changeset,
  revision: Option(StableId),
) -> change.TaggedChange {
  change.TaggedChange(revision, None, value)
}

fn run_operation(
  state: Execution,
  operation: JsonValue,
  revisions: codec.Revisions,
  identity_order: change.IdentityOrder,
) -> Result(Execution, String) {
  use id <- result.try(codec.field(operation, "id", codec.text))
  use _ <- result.try(case id == "" || list.contains(state.ids, id) {
    True -> Error("empty or repeated modular result identifier")
    False -> Ok(Nil)
  })
  use evaluation <- result.try(
    evaluate(operation, state.changes, revisions, identity_order)
    |> result.map_error(fn(detail) { id <> ": " <> detail }),
  )
  let header = [
    #("operation", json.string("modular")),
    #("id", json.string(id)),
  ]
  case evaluation.change {
    None ->
      Ok(
        Execution(..state, ids: [id, ..state.ids], observations: [
          json.object(list.append(header, [#("accepted", json.bool(False))])),
          ..state.observations
        ]),
      )
    Some(value) -> {
      use delta <- result.try(
        change.into_delta(value)
        |> codec.native
        |> result.map_error(fn(detail) { id <> ": delta: " <> detail }),
      )
      let observation =
        json.object(
          list.append(header, [
            #("accepted", json.bool(True)),
            #("change", codec.state_json(value.change)),
            #("delta", codec.delta_json(delta)),
            ..evaluation.extra
          ]),
        )
      Ok(
        Execution(
          changes: [#(id, value), ..state.changes],
          ids: [id, ..state.ids],
          observations: [observation, ..state.observations],
        ),
      )
    }
  }
}

fn evaluate(
  operation: JsonValue,
  changes: Changes,
  revisions: codec.Revisions,
  identity_order: change.IdentityOrder,
) -> Result(Evaluation, String) {
  let decode_revision = fn(value) {
    use revision <- result.try(codec.revision(value))
    use _ <- result.try(codec.wire_revision(revision, revisions))
    Ok(revision)
  }
  use selector <- result.try(codec.field(operation, "op", codec.text))
  case selector {
    "edit" -> {
      use _ <- result.try(
        codec.exact(operation, [
          "id", "op", "revision", "schema", "root", "path", "value",
        ]),
      )
      use revision <- result.try(codec.field(
        operation,
        "revision",
        decode_revision,
      ))
      use raw_schema <- result.try(codec.field(operation, "schema", codec.text))
      use stored <- result.try(
        schema.stored_from_string(raw_schema) |> codec.native,
      )
      use root <- result.try(
        codec.field(operation, "root", fn(value) {
          codec.optional(value, codec.tree)
        }),
      )
      use tree <- result.try(forest.new(revision, stored, root) |> codec.native)
      use path <- result.try(
        codec.field(operation, "path", fn(value) {
          codec.many(value, codec.text)
        }),
      )
      use value <- result.try(
        codec.field(operation, "value", fn(value) {
          codec.optional(value, codec.tree)
        }),
      )
      let edit = case value {
        None -> types.ClearField(path)
        Some(value) -> types.SetField(path, value)
      }
      use authored <- result.try(
        change.edit(stored, tree, revision, edit, identity_order)
        |> codec.native,
      )
      Ok(Evaluation(Some(retag(authored, Some(revision))), []))
    }
    "compose" -> {
      use _ <- result.try(codec.exact(operation, ["id", "op", "changes"]))
      use operands <- result.try(
        codec.field(operation, "changes", fn(value) {
          codec.many(value, fn(value) {
            use name <- result.try(codec.text(value))
            find(changes, name)
          })
        }),
      )
      use composed <- result.try(change.compose(operands) |> codec.native)
      Ok(Evaluation(Some(retag(composed, None)), []))
    }
    "invert" -> {
      use _ <- result.try(
        codec.exact(operation, [
          "id", "op", "change", "isRollback", "inverseRevision",
        ]),
      )
      use original <- result.try(operand(operation, "change", changes))
      use rollback <- result.try(codec.field(
        operation,
        "isRollback",
        codec.boolean,
      ))
      use revision <- result.try(codec.field(
        operation,
        "inverseRevision",
        decode_revision,
      ))
      use inverted <- result.try(
        change.invert(original, rollback, revision) |> codec.native,
      )
      Ok(Evaluation(Some(retag(inverted, Some(revision))), []))
    }
    "rebase" -> {
      use _ <- result.try(
        codec.exact(operation, [
          "id", "op", "change", "over", "revisionMetadata",
        ]),
      )
      use original <- result.try(operand(operation, "change", changes))
      use over <- result.try(operand(operation, "over", changes))
      use metadata <- result.try(
        codec.field(operation, "revisionMetadata", fn(value) {
          codec.many(value, fn(value) {
            use info <- result.try(codec.revision_info(value))
            use _ <- result.try(codec.wire_revision(info.revision, revisions))
            use _ <- result.try(case info.rollback_of {
              None -> Ok(Nil)
              Some(revision) ->
                codec.wire_revision(revision, revisions)
                |> result.map(fn(_) { Nil })
            })
            Ok(info)
          })
        }),
      )
      use context <- result.try(change.rebase_context(metadata) |> codec.native)
      use rebased <- result.try(
        change.rebase(original, over, context) |> codec.native,
      )
      Ok(Evaluation(Some(retag(rebased, original.revision)), []))
    }
    "replace-revisions" -> {
      use _ <- result.try(
        codec.exact(operation, ["id", "op", "change", "obsolete", "updated"]),
      )
      use original <- result.try(operand(operation, "change", changes))
      use obsolete <- result.try(
        codec.field(operation, "obsolete", fn(value) {
          codec.many(value, fn(value) { codec.optional(value, decode_revision) })
        }),
      )
      use updated <- result.try(codec.field(
        operation,
        "updated",
        decode_revision,
      ))
      case change.replace_revisions(original.change, obsolete, updated) {
        Ok(replaced) -> Ok(Evaluation(Some(retag(replaced, Some(updated))), []))
        Error(types.CorruptData("node changes", "live node change is missing")) ->
          Ok(Evaluation(None, []))
        Error(error) -> codec.native(Error(error))
      }
    }
    "prune" -> {
      use _ <- result.try(codec.exact(operation, ["id", "op", "change"]))
      use original <- result.try(operand(operation, "change", changes))
      use pruned <- result.try(change.prune(original.change) |> codec.native)
      Ok(Evaluation(Some(retag(pruned, original.revision)), []))
    }
    "refreshers" -> {
      use _ <- result.try(
        codec.exact(operation, ["id", "op", "change", "roots", "repair"]),
      )
      use original <- result.try(operand(operation, "change", changes))
      use roots <- result.try(
        codec.field(operation, "roots", fn(value) {
          codec.many(value, codec.atom)
        }),
      )
      use repair <- result.try(
        codec.field(operation, "repair", fn(value) {
          codec.many(value, codec.build)
        }),
      )
      use removed <- result.try(
        change.relevant_removed_roots(original.change) |> codec.native,
      )
      use refreshed <- result.try(
        change.update_refreshers(original.change, roots, repair) |> codec.native,
      )
      Ok(
        Evaluation(Some(retag(refreshed, original.revision)), [
          #("removedRoots", json.array(removed, codec.atom_json)),
        ]),
      )
    }
    _ -> Error("unsupported modular operation: " <> selector)
  }
}

fn run_forests(
  scenarios: List(JsonValue),
  changes: Changes,
) -> Result(List(Json), String) {
  use scenarios <- result.try(
    list.try_map(scenarios, fn(scenario) {
      use _ <- result.try(
        codec.exact(scenario, ["id", "schema", "root", "actions"]),
      )
      use id <- result.try(codec.field(scenario, "id", codec.text))
      use schema <- result.try(codec.field(scenario, "schema", codec.text))
      use root <- result.try(codec.get(scenario, "root"))
      use actions <- result.try(codec.field(scenario, "actions", codec.items))
      use actions <- result.try(
        list.try_map(actions, fn(action) {
          use selector <- result.try(codec.field(action, "op", codec.text))
          case selector {
            "apply" -> {
              use _ <- result.try(codec.exact(action, ["id", "op", "change"]))
              use id <- result.try(codec.field(action, "id", codec.text))
              use change <- result.try(operand(action, "change", changes))
              use delta <- result.try(change.into_delta(change) |> codec.native)
              Ok(
                json.object([
                  #("id", json.string(id)),
                  #("op", json.string("apply")),
                  #("delta", codec.delta_json(delta)),
                ]),
              )
            }
            "retain" | "observe" -> Ok(json_ot.to_json(action))
            _ -> Error("unsupported modular forest action: " <> selector)
          }
        }),
      )
      Ok(
        json.object([
          #("id", json.string(id)),
          #("schema", json.string(schema)),
          #("root", json_ot.to_json(root)),
          #("actions", codec.array(actions)),
        ]),
      )
    }),
  )
  use output <- result.try(
    forest_fixture.run(
      json.object([
        #("scenarios", codec.array(scenarios)),
      ]),
    ),
  )
  use output <- result.try(codec.parse(output))
  use observations <- result.try(codec.field(
    output,
    "observations",
    codec.items,
  ))
  list.try_map(observations, fn(observation) {
    case observation {
      VObject(fields) ->
        Ok(
          json.object([
            #("operation", json.string("modular-forest")),
            ..list.map(fields, fn(entry) {
              #(entry.0, json_ot.to_json(entry.1))
            })
          ]),
        )
      _ -> Error("invalid native forest observation")
    }
  })
}

fn original_observations(
  input: JsonValue,
  changes: Changes,
  revisions: codec.Revisions,
) -> Result(List(Json), String) {
  use operations <- result.try(codec.get(input, "operations"))
  use _ <- result.try(
    codec.exact(operations, [
      "compose", "invert", "rebase", "replaceRevisions", "prune", "refreshers",
    ]),
  )
  list.try_map(
    ["compose", "invert", "rebase", "replaceRevisions", "prune", "refreshers"],
    fn(selector) {
      use operation <- result.try(codec.get(operations, selector))
      use #(output, extra) <- result.try(original_operation(
        selector,
        operation,
        changes,
        revisions,
      ))
      use encoded <- result.try(codec.wire(output, revisions))
      let selector = case selector {
        "replaceRevisions" -> "replace-revisions"
        other -> other
      }
      Ok(
        json.object([
          #("operation", json.string(selector)),
          #("encoded", encoded),
          ..extra
        ]),
      )
    },
  )
}

fn original_operation(
  selector: String,
  operation: JsonValue,
  changes: Changes,
  revisions: codec.Revisions,
) -> Result(#(change.Changeset, List(#(String, Json))), String) {
  let decode_revision = fn(value) { decoded_revision(value, revisions) }
  case selector {
    "compose" -> {
      use _ <- result.try(codec.exact(operation, ["changes", "revisions"]))
      use names <- result.try(
        codec.field(operation, "changes", fn(value) {
          codec.many(value, codec.text)
        }),
      )
      use tags <- result.try(
        codec.field(operation, "revisions", fn(value) {
          codec.many(value, decode_revision)
        }),
      )
      use _ <- result.try(case list.length(names) == list.length(tags) {
        True -> Ok(Nil)
        False -> Error("compose operands and revisions have different lengths")
      })
      use tagged <- result.try(
        list.try_map(list.zip(names, tags), fn(entry) {
          use change <- result.try(find(changes, entry.0))
          Ok(retag(change.change, Some(entry.1)))
        }),
      )
      use output <- result.try(change.compose(tagged) |> codec.native)
      Ok(#(output, []))
    }
    "invert" -> {
      use _ <- result.try(
        codec.exact(operation, [
          "change", "revision", "isRollback", "inverseRevision",
        ]),
      )
      use original <- result.try(operand(operation, "change", changes))
      use tag <- result.try(codec.field(operation, "revision", decode_revision))
      use rollback <- result.try(codec.field(
        operation,
        "isRollback",
        codec.boolean,
      ))
      use inverse <- result.try(codec.field(
        operation,
        "inverseRevision",
        decode_revision,
      ))
      use output <- result.try(
        change.invert(retag(original.change, Some(tag)), rollback, inverse)
        |> codec.native,
      )
      Ok(#(output, []))
    }
    "rebase" -> {
      use _ <- result.try(
        codec.exact(operation, [
          "change", "revision", "over", "overRevision", "revisionMetadata",
        ]),
      )
      use original <- result.try(operand(operation, "change", changes))
      use over <- result.try(operand(operation, "over", changes))
      use tag <- result.try(codec.field(operation, "revision", decode_revision))
      use over_tag <- result.try(codec.field(
        operation,
        "overRevision",
        decode_revision,
      ))
      use metadata <- result.try(
        codec.field(operation, "revisionMetadata", fn(value) {
          codec.many(value, decode_revision)
        }),
      )
      use context <- result.try(
        change.rebase_context(
          list.map(metadata, fn(id) { change.RevisionInfo(id, None) }),
        )
        |> codec.native,
      )
      use output <- result.try(
        change.rebase(
          retag(original.change, Some(tag)),
          retag(over.change, Some(over_tag)),
          context,
        )
        |> codec.native,
      )
      Ok(#(output, []))
    }
    "replaceRevisions" -> {
      use _ <- result.try(
        codec.exact(operation, ["change", "obsolete", "updated"]),
      )
      use original <- result.try(operand(operation, "change", changes))
      use obsolete <- result.try(
        codec.field(operation, "obsolete", fn(value) {
          codec.many(value, fn(value) { codec.optional(value, decode_revision) })
        }),
      )
      use updated <- result.try(codec.field(
        operation,
        "updated",
        decode_revision,
      ))
      use output <- result.try(
        change.replace_revisions(original.change, obsolete, updated)
        |> codec.native,
      )
      Ok(#(output, []))
    }
    "prune" -> {
      use _ <- result.try(codec.exact(operation, ["change"]))
      use original <- result.try(operand(operation, "change", changes))
      use output <- result.try(change.prune(original.change) |> codec.native)
      Ok(#(output, []))
    }
    "refreshers" -> {
      use _ <- result.try(codec.exact(operation, ["change", "roots"]))
      use original <- result.try(operand(operation, "change", changes))
      use repair <- result.try(
        codec.field(operation, "roots", fn(value) {
          codec.many(value, fn(value) {
            use _ <- result.try(codec.exact(value, ["id", "trees"]))
            use raw_id <- result.try(codec.get(value, "id"))
            use _ <- result.try(codec.exact(raw_id, ["minor", "major"]))
            use minor <- result.try(codec.field(raw_id, "minor", codec.integer))
            use major <- result.try(codec.field(
              raw_id,
              "major",
              decode_revision,
            ))
            use trees <- result.try(
              codec.field(value, "trees", fn(value) {
                codec.many(value, fn(value) {
                  codec.text(value) |> result.map(types.StringValue)
                })
              }),
            )
            Ok(forest.Build(types.AtomId(Some(major), minor), trees))
          })
        }),
      )
      use removed <- result.try(
        change.relevant_removed_roots(original.change) |> codec.native,
      )
      use roots <- result.try(
        list.try_map(removed, fn(root) {
          case root.revision {
            None ->
              Error("original removed-root observation requires a revision")
            Some(revision) -> {
              use major <- result.try(codec.wire_revision(revision, revisions))
              Ok(
                json.object([
                  #("minor", json.int(root.local_id)),
                  #("major", json.int(major)),
                ]),
              )
            }
          }
        }),
      )
      use output <- result.try(
        change.update_refreshers(
          original.change,
          list.map(repair, fn(build) { build.id }),
          repair,
        )
        |> codec.native,
      )
      Ok(#(output, [#("removedRoots", codec.array(roots))]))
    }
    _ -> Error("unknown original modular operation")
  }
}
