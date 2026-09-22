import gleam/bit_array
import gleam/crypto
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam/uri
import watershed/wire
import watershed/wire/fluid_summary

type Input {
  Input(snapshot: Snapshot, scenarios: List(Scenario))
}

type Snapshot {
  Snapshot(tree_json: Json, tree: SnapshotNode, blobs: Dict(String, BitArray))
}

type SnapshotNode {
  SnapshotNode(
    id: String,
    blobs: Dict(String, String),
    trees: Dict(String, SnapshotNode),
  )
}

type Scenario {
  Scenario(label: String, entries: List(InputEntry))
}

type InputEntry {
  BlobInput(name: String, bytes: BitArray)
  TreeInput(name: String, entries: List(InputEntry))
  HandleInput(name: String, path: String, kind: fluid_summary.HandleKind)
}

type Allocation {
  Allocation(next: Int, trees: Dict(String, String))
}

pub fn run(input: Json) -> Result(Json, String) {
  use decoded <- result.try(
    json.parse(json.to_string(input), input_decoder())
    |> result.map_error(fn(error) {
      "invalid summary fixture: " <> string.inspect(error)
    }),
  )
  use previous <- result.try(
    fluid_summary.from_snapshot(
      decoded.snapshot.tree_json,
      decoded.snapshot.blobs,
    )
    |> result.map_error(summary_error),
  )
  use observations <- result.try(
    list.try_map(decoded.scenarios, fn(scenario) {
      run_scenario(scenario, decoded.snapshot.tree, previous)
    }),
  )
  Ok(json.object([#("observations", array(observations))]))
}

fn run_scenario(
  scenario: Scenario,
  snapshot: SnapshotNode,
  previous: fluid_summary.SummaryEntry,
) -> Result(Json, String) {
  let summary = fluid_summary.SummaryTree(to_summary_entries(scenario.entries))
  case scenario.label {
    "snapshot-entries" -> {
      use entries <- result.try(observe_snapshot(snapshot, previous, []))
      Ok(
        json.object([
          #("label", json.string(scenario.label)),
          #("entries", array(entries)),
        ]),
      )
    }
    "emitted-entries" -> {
      use resolved <- result.try(
        fluid_summary.resolve(summary, Some(previous))
        |> result.map_error(summary_error),
      )
      let allocation =
        allocate_trees(scenario.entries, [], Allocation(1, dict.new()))
      let assert fluid_summary.SummaryTree(entries) = resolved
      use observed <- result.try(
        observe_entries(
          scenario.entries,
          entries,
          snapshot,
          allocation.trees,
          [],
        ),
      )
      Ok(
        json.object([
          #("label", json.string(scenario.label)),
          #("entries", array(observed)),
        ]),
      )
    }
    _ -> {
      let previous = case scenario.label {
        "missing-parent" -> None
        _ -> Some(previous)
      }
      case fluid_summary.resolve(summary, previous) {
        Ok(_) -> Error("summary scenario did not fail: " <> scenario.label)
        Error(_) ->
          Ok(
            json.object([
              #("label", json.string(scenario.label)),
              #("refused", json.bool(True)),
            ]),
          )
      }
    }
  }
}

fn observe_snapshot(
  snapshot: SnapshotNode,
  resolved: fluid_summary.SummaryEntry,
  components: List(String),
) -> Result(List(Json), String) {
  let assert fluid_summary.SummaryTree(entries) = resolved
  let root =
    json.object([
      #("components", json.array(components, json.string)),
      #("kind", json.string("tree")),
      #("storageId", json.string(snapshot.id)),
    ])
  let names =
    list.append(
      snapshot.blobs
        |> dict.to_list
        |> list.map(fn(entry) { entry.0 }),
      snapshot.trees
        |> dict.to_list
        |> list.map(fn(entry) { entry.0 }),
    )
    |> list.sort(string.compare)
  use children <- result.try(
    list.try_fold(names, [], fn(observed, name) {
      use value <- result.try(
        entries
        |> list.find(fn(entry) { entry.0 == name })
        |> result.map(fn(entry) { entry.1 })
        |> result.map_error(fn(_) {
          "snapshot materialization omitted " <> path_key([name])
        }),
      )
      let path = list.append(components, [name])
      case dict.get(snapshot.blobs, name), dict.get(snapshot.trees, name) {
        Ok(blob_id), Error(Nil) -> {
          let assert fluid_summary.SummaryBlob(bytes) = value
          Ok(
            list.append(observed, [
              json.object([
                #("components", json.array(path, json.string)),
                #("kind", json.string("blob")),
                #("storageId", json.string(blob_id)),
                #("bytes", json.string(bit_array.base64_encode(bytes, True))),
              ]),
            ]),
          )
        }
        Error(Nil), Ok(tree) -> {
          use nested <- result.try(observe_snapshot(tree, value, path))
          Ok(list.append(observed, nested))
        }
        _, _ -> Error("snapshot has a blob and tree collision at " <> name)
      }
    }),
  )
  Ok([root, ..children])
}

fn observe_entries(
  inputs: List(InputEntry),
  resolved: List(#(String, fluid_summary.SummaryEntry)),
  snapshot: SnapshotNode,
  tree_ids: Dict(String, String),
  parent: List(String),
) -> Result(List(Json), String) {
  case inputs, resolved {
    [], [] -> Ok([])
    [input, ..input_rest], [entry, ..resolved_rest] -> {
      let name = input_name(input)
      case entry.0 == name {
        False -> Error("resolved summary entry order changed at " <> name)
        True -> {
          let components = list.append(parent, [name])
          use current <- result.try(observe_entry(
            input,
            entry.1,
            snapshot,
            tree_ids,
            components,
          ))
          use rest <- result.try(observe_entries(
            input_rest,
            resolved_rest,
            snapshot,
            tree_ids,
            parent,
          ))
          Ok(list.append(current, rest))
        }
      }
    }
    _, _ -> Error("resolved summary entry count changed")
  }
}

fn observe_entry(
  input: InputEntry,
  resolved: fluid_summary.SummaryEntry,
  snapshot: SnapshotNode,
  tree_ids: Dict(String, String),
  components: List(String),
) -> Result(List(Json), String) {
  let name = input_name(input)
  let base = [
    #("components", json.array(components, json.string)),
    #("encodedName", json.string(fluid_summary.encode_component(name))),
  ]
  case input, resolved {
    BlobInput(_, _), fluid_summary.SummaryBlob(bytes) ->
      Ok([
        json.object(
          list.append(base, [
            #("kind", json.string("blob")),
            #("mode", json.string("100644")),
            #("storageId", json.string(git_blob_hash(bytes))),
            #("source", json.string("uploaded")),
            #("bytes", json.string(bit_array.base64_encode(bytes, True))),
          ]),
        ),
      ])
    TreeInput(_, inputs), fluid_summary.SummaryTree(entries) -> {
      use tree_id <- result.try(
        dict.get(tree_ids, path_key(components))
        |> result.map_error(fn(_) {
          "missing allocated tree id at " <> path_key(components)
        }),
      )
      use children <- result.try(observe_entries(
        inputs,
        entries,
        snapshot,
        tree_ids,
        components,
      ))
      Ok([
        json.object(
          list.append(base, [
            #("kind", json.string("tree")),
            #("mode", json.string("040000")),
            #("storageId", json.string(tree_id)),
            #("source", json.string("uploaded")),
          ]),
        ),
        ..children
      ])
    }
    HandleInput(_, path, kind), value -> {
      use storage_id <- result.try(
        snapshot_id(snapshot, path, kind)
        |> result.map_error(summary_error),
      )
      let common =
        list.append(base, [
          #("kind", json.string(handle_kind(kind))),
          #("mode", json.string(handle_mode(kind))),
          #("storageId", json.string(storage_id)),
          #("source", json.string("previous")),
        ])
      case kind, value {
        fluid_summary.BlobHandle, fluid_summary.SummaryBlob(bytes) ->
          Ok([
            json.object(
              list.append(common, [
                #("bytes", json.string(bit_array.base64_encode(bytes, True))),
              ]),
            ),
          ])
        fluid_summary.TreeHandle, fluid_summary.SummaryTree(_) ->
          Ok([json.object(common)])
        _, _ -> Error("resolved handle has the wrong kind at " <> path)
      }
    }
    _, _ -> Error("resolved summary entry has the wrong kind at " <> name)
  }
}

fn allocate_trees(
  entries: List(InputEntry),
  parent: List(String),
  allocation: Allocation,
) -> Allocation {
  list.fold(entries, allocation, fn(allocation, entry) {
    case entry {
      TreeInput(name, children) -> {
        let components = list.append(parent, [name])
        let allocation = allocate_trees(children, components, allocation)
        Allocation(
          next: allocation.next + 1,
          trees: dict.insert(
            allocation.trees,
            path_key(components),
            "created-tree-" <> int.to_string(allocation.next),
          ),
        )
      }
      _ -> allocation
    }
  })
}

fn git_blob_hash(bytes: BitArray) -> String {
  crypto.hash(crypto.Sha1, <<
    "blob ":utf8,
    int.to_string(bit_array.byte_size(bytes)):utf8,
    0,
    bytes:bits,
  >>)
  |> bit_array.base16_encode
  |> string.lowercase
}

fn snapshot_id(
  snapshot: SnapshotNode,
  path: String,
  kind: fluid_summary.HandleKind,
) -> Result(String, fluid_summary.SummaryError) {
  use components <- result.try(decode_path(path))
  snapshot_id_at(snapshot, components, path, kind)
}

fn snapshot_id_at(
  snapshot: SnapshotNode,
  components: List(String),
  original_path: String,
  kind: fluid_summary.HandleKind,
) -> Result(String, fluid_summary.SummaryError) {
  case components {
    [] ->
      case kind {
        fluid_summary.TreeHandle -> Ok(snapshot.id)
        fluid_summary.BlobHandle ->
          Error(fluid_summary.WrongKind(original_path, fluid_summary.BlobHandle))
      }
    [name] ->
      case kind {
        fluid_summary.BlobHandle ->
          dict.get(snapshot.blobs, name)
          |> result.replace_error(fluid_summary.MissingEntry(original_path))
        fluid_summary.TreeHandle ->
          dict.get(snapshot.trees, name)
          |> result.map(fn(tree) { tree.id })
          |> result.replace_error(fluid_summary.MissingEntry(original_path))
      }
    [name, ..rest] -> {
      use tree <- result.try(
        dict.get(snapshot.trees, name)
        |> result.replace_error(fluid_summary.MissingEntry(original_path)),
      )
      snapshot_id_at(tree, rest, original_path, kind)
    }
  }
}

fn decode_path(
  path: String,
) -> Result(List(String), fluid_summary.SummaryError) {
  let parts = case string.split(path, "/") {
    ["", ..rest] -> rest
    parts -> parts
  }
  parts
  |> list.try_map(fn(part) {
    uri.percent_decode(part)
    |> result.replace_error(fluid_summary.MalformedEntry(
      path,
      "invalid percent encoding",
    ))
  })
}

fn input_name(entry: InputEntry) -> String {
  case entry {
    BlobInput(name, _) | TreeInput(name, _) | HandleInput(name, _, _) -> name
  }
}

fn to_summary_entries(
  entries: List(InputEntry),
) -> List(#(String, fluid_summary.SummaryEntry)) {
  list.map(entries, fn(entry) {
    case entry {
      BlobInput(name, bytes) -> #(name, fluid_summary.SummaryBlob(bytes))
      TreeInput(name, children) -> #(
        name,
        fluid_summary.SummaryTree(to_summary_entries(children)),
      )
      HandleInput(name, path, kind) -> #(
        name,
        fluid_summary.SummaryHandle(path, kind),
      )
    }
  })
}

fn handle_kind(kind: fluid_summary.HandleKind) -> String {
  case kind {
    fluid_summary.BlobHandle -> "blob"
    fluid_summary.TreeHandle -> "tree"
  }
}

fn handle_mode(kind: fluid_summary.HandleKind) -> String {
  case kind {
    fluid_summary.BlobHandle -> "100644"
    fluid_summary.TreeHandle -> "040000"
  }
}

fn path_key(components: List(String)) -> String {
  string.join(components, "\u{0}")
}

fn summary_error(error: fluid_summary.SummaryError) -> String {
  string.inspect(error)
}

fn input_decoder() -> decode.Decoder(Input) {
  use snapshot <- decode.field("previousSnapshot", snapshot_decoder())
  use scenarios <- decode.field("scenarios", decode.list(scenario_decoder()))
  decode.success(Input(snapshot:, scenarios:))
}

fn snapshot_decoder() -> decode.Decoder(Snapshot) {
  use encoding <- decode.field("blobEncoding", decode.string)
  case encoding {
    "base64" -> {
      use tree_dynamic <- decode.field("tree", decode.dynamic)
      use tree <- decode.field("tree", snapshot_node_decoder())
      use encoded_blobs <- decode.field(
        "blobs",
        decode.dict(decode.string, decode.string),
      )
      case decode_snapshot_blobs(encoded_blobs) {
        Ok(blobs) ->
          decode.success(Snapshot(
            tree_json: wire.dynamic_to_json(tree_dynamic),
            tree:,
            blobs:,
          ))
        Error(_) ->
          decode.failure(
            Snapshot(json.object([]), empty_snapshot(), dict.new()),
            "base64 snapshot blobs",
          )
      }
    }
    _ ->
      decode.failure(
        Snapshot(json.object([]), empty_snapshot(), dict.new()),
        "base64 snapshot encoding",
      )
  }
}

fn snapshot_node_decoder() -> decode.Decoder(SnapshotNode) {
  use id <- decode.field("id", decode.string)
  use blobs <- decode.field("blobs", decode.dict(decode.string, decode.string))
  use trees <- decode.field(
    "trees",
    decode.dict(decode.string, decode.recursive(snapshot_node_decoder)),
  )
  use _commits <- decode.optional_field(
    "commits",
    dict.new(),
    decode.dict(decode.string, decode.dynamic),
  )
  decode.success(SnapshotNode(id:, blobs:, trees:))
}

fn scenario_decoder() -> decode.Decoder(Scenario) {
  use label <- decode.field("label", decode.string)
  use entries <- decode.optional_field(
    "summary",
    [],
    decode.list(input_entry_decoder()),
  )
  decode.success(Scenario(label:, entries:))
}

fn input_entry_decoder() -> decode.Decoder(InputEntry) {
  use name <- decode.field("name", decode.string)
  use kind <- decode.field("kind", decode.string)
  case kind {
    "blob" -> {
      use encoded <- decode.field("bytes", decode.string)
      case bit_array.base64_decode(encoded) {
        Ok(bytes) -> decode.success(BlobInput(name, bytes))
        Error(_) -> decode.failure(BlobInput("", <<>>), "base64 summary blob")
      }
    }
    "tree" -> {
      use entries <- decode.field(
        "entries",
        decode.list(decode.recursive(input_entry_decoder)),
      )
      decode.success(TreeInput(name, entries))
    }
    "handle" -> {
      use path <- decode.field("path", decode.string)
      use handle_kind <- decode.field("handleKind", decode.string)
      case handle_kind {
        "blob" ->
          decode.success(HandleInput(name, path, fluid_summary.BlobHandle))
        "tree" ->
          decode.success(HandleInput(name, path, fluid_summary.TreeHandle))
        _ -> decode.failure(BlobInput("", <<>>), "summary handle kind")
      }
    }
    _ -> decode.failure(BlobInput("", <<>>), "summary entry kind")
  }
}

fn decode_snapshot_blobs(
  encoded: Dict(String, String),
) -> Result(Dict(String, BitArray), String) {
  encoded
  |> dict.to_list
  |> list.try_fold(dict.new(), fn(blobs, entry) {
    use bytes <- result.try(
      bit_array.base64_decode(entry.1)
      |> result.replace_error("invalid snapshot blob: " <> entry.0),
    )
    Ok(dict.insert(blobs, entry.0, bytes))
  })
}

fn empty_snapshot() -> SnapshotNode {
  SnapshotNode("", dict.new(), dict.new())
}

fn array(values: List(Json)) -> Json {
  json.array(values, fn(value) { value })
}
