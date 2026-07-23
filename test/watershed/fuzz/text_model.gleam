import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import lattice_core/replica_id
import lattice_text/text.{type Text}
import qcheck
import watershed/fuzz/kernel_fuzz.{type KernelModel, Capabilities, KernelModel}
import watershed/text_kernel

pub type TextCommand {
  InsertCmd(index_seed: Int, value: String, delta: Option(Text))
  DeleteRangeCmd(start_seed: Int, end_seed: Int, delta: Option(Text))
  ReplaceRangeCmd(
    start_seed: Int,
    end_seed: Int,
    value: String,
    delta: Option(Text),
  )
  AppendCmd(value: String, delta: Option(Text))
}

fn delta_to_json(delta: Option(Text)) -> Json {
  case delta {
    None -> json.null()
    Some(delta) -> json.string(json.to_string(text.to_json(delta)))
  }
}

fn delta_decoder() -> decode.Decoder(Option(Text)) {
  decode.optional(decode.string)
  |> decode.then(fn(maybe_encoded) {
    case maybe_encoded {
      None -> decode.success(None)
      Some(encoded) ->
        case text.from_json(encoded) {
          Ok(delta) -> decode.success(Some(delta))
          Error(_) -> decode.failure(None, "text delta")
        }
    }
  })
}

fn op_to_json(command: TextCommand) -> Json {
  case command {
    InsertCmd(index_seed, value, delta) ->
      json.object([
        #("tag", json.string("Insert")),
        #("index_seed", json.int(index_seed)),
        #("value", json.string(value)),
        #("delta", delta_to_json(delta)),
      ])
    DeleteRangeCmd(start_seed, end_seed, delta) ->
      json.object([
        #("tag", json.string("DeleteRange")),
        #("start_seed", json.int(start_seed)),
        #("end_seed", json.int(end_seed)),
        #("delta", delta_to_json(delta)),
      ])
    ReplaceRangeCmd(start_seed, end_seed, value, delta) ->
      json.object([
        #("tag", json.string("ReplaceRange")),
        #("start_seed", json.int(start_seed)),
        #("end_seed", json.int(end_seed)),
        #("value", json.string(value)),
        #("delta", delta_to_json(delta)),
      ])
    AppendCmd(value, delta) ->
      json.object([
        #("tag", json.string("Append")),
        #("value", json.string(value)),
        #("delta", delta_to_json(delta)),
      ])
  }
}

fn op_decoder() -> decode.Decoder(TextCommand) {
  use tag <- decode.field("tag", decode.string)
  case tag {
    "Insert" -> {
      use index_seed <- decode.field("index_seed", decode.int)
      use value <- decode.field("value", decode.string)
      use delta <- decode.field("delta", delta_decoder())
      decode.success(InsertCmd(index_seed, value, delta))
    }
    "DeleteRange" -> {
      use start_seed <- decode.field("start_seed", decode.int)
      use end_seed <- decode.field("end_seed", decode.int)
      use delta <- decode.field("delta", delta_decoder())
      decode.success(DeleteRangeCmd(start_seed, end_seed, delta))
    }
    "ReplaceRange" -> {
      use start_seed <- decode.field("start_seed", decode.int)
      use end_seed <- decode.field("end_seed", decode.int)
      use value <- decode.field("value", decode.string)
      use delta <- decode.field("delta", delta_decoder())
      decode.success(ReplaceRangeCmd(start_seed, end_seed, value, delta))
    }
    "Append" -> {
      use value <- decode.field("value", decode.string)
      use delta <- decode.field("delta", delta_decoder())
      decode.success(AppendCmd(value, delta))
    }
    _ -> decode.failure(InsertCmd(0, "", None), "text command")
  }
}

/// A grapheme-heavy alphabet: plain ASCII, a combining-mark cluster
/// ("e" + U+0301 combining acute), a ZWJ-joined family emoji (many
/// codepoints, one grapheme), a simple emoji, a flag (regional-indicator
/// pair, one grapheme), three non-Latin scripts, and the empty string —
/// so generated commands naturally explore the no-op paths (`insert("")`,
/// `append("")`, a zero-length `delete_range`/`replace_range`) alongside
/// real multi-grapheme edits.
fn alphabet() -> List(String) {
  let family =
    "👩" <> "\u{200D}" <> "👩" <> "\u{200D}" <> "👧" <> "\u{200D}" <> "👦"
  [
    "", "a", "b", "c", "e\u{0301}", "n\u{0303}", "😀", "👍", family, "🇺🇸", "日", "д",
    "अ",
  ]
}

fn value_for(seed: Int) -> String {
  let choices = alphabet()
  let assert Ok(value) =
    list.first(list.drop(choices, seed % list.length(choices)))
  value
}

/// A guaranteed non-empty fallback value, used where a command must
/// actually produce an op (e.g. when a zero-length text needs seeding, or
/// `apply_stashed` must route *something* for a freshly generated command
/// that happened to be a no-op).
fn fallback_value(seed: Int) -> String {
  case value_for(seed) {
    "" -> "x"
    other -> other
  }
}

fn op_generator() -> qcheck.Generator(TextCommand) {
  qcheck.tuple4(
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
  )
  |> qcheck.map(fn(parts) {
    let value = value_for(parts.3)
    case parts.0 % 4 {
      0 -> InsertCmd(parts.1, value, None)
      1 -> DeleteRangeCmd(parts.1, parts.2, None)
      2 -> ReplaceRangeCmd(parts.1, parts.2, value, None)
      _ -> AppendCmd(value, None)
    }
  })
}

fn to_kernel_op(command: TextCommand, context: String) -> text_kernel.TextOp {
  case command {
    InsertCmd(index, value, Some(delta)) ->
      text_kernel.Insert(index, value, delta)
    DeleteRangeCmd(start, end, Some(delta)) ->
      text_kernel.DeleteRange(start, end, delta)
    ReplaceRangeCmd(start, end, value, Some(delta)) ->
      text_kernel.ReplaceRange(start, end, value, delta)
    AppendCmd(value, Some(delta)) -> text_kernel.Append(value, delta)
    InsertCmd(_, _, None)
    | DeleteRangeCmd(_, _, None)
    | ReplaceRangeCmd(_, _, _, None)
    | AppendCmd(_, None) ->
      panic as {
        context
        <> " received an op without a delta — submit/apply_stashed must rewrite ops before routing"
      }
  }
}

fn submit_insert(
  state: text_kernel.TextState,
  index_seed: Int,
  value: String,
) -> #(text_kernel.TextState, Option(TextCommand)) {
  let index = index_seed % { text_kernel.length(state) + 1 }
  let assert Ok(#(state, _events, submission)) =
    text_kernel.insert(state, index, value)
  case submission {
    None -> #(state, None)
    Some(text_kernel.Submission(op, _message_id)) -> {
      let assert text_kernel.Insert(index, value, delta) = op
      #(state, Some(InsertCmd(index, value, Some(delta))))
    }
  }
}

fn submit(
  state: text_kernel.TextState,
  command: TextCommand,
  _meta: kernel_fuzz.SubmitMeta,
) -> #(text_kernel.TextState, Option(TextCommand)) {
  let length = text_kernel.length(state)
  case command {
    InsertCmd(index_seed, value, _) -> submit_insert(state, index_seed, value)
    DeleteRangeCmd(start_seed, end_seed, _) -> {
      let a = start_seed % { length + 1 }
      let b = end_seed % { length + 1 }
      let start = int.min(a, b)
      let end = int.max(a, b)
      let assert Ok(#(state, _events, submission)) =
        text_kernel.delete_range(state, start, end)
      case submission {
        None -> #(state, None)
        Some(text_kernel.Submission(op, _message_id)) -> {
          let assert text_kernel.DeleteRange(start, end, delta) = op
          #(state, Some(DeleteRangeCmd(start, end, Some(delta))))
        }
      }
    }
    ReplaceRangeCmd(start_seed, end_seed, value, _) -> {
      let a = start_seed % { length + 1 }
      let b = end_seed % { length + 1 }
      let start = int.min(a, b)
      let end = int.max(a, b)
      submit_replace(state, start, end, value)
    }
    AppendCmd(value, _) -> {
      let #(state, _events, submission) = text_kernel.append(state, value)
      case submission {
        None -> #(state, None)
        Some(text_kernel.Submission(op, _message_id)) -> {
          let assert text_kernel.Append(value, delta) = op
          #(state, Some(AppendCmd(value, Some(delta))))
        }
      }
    }
  }
}

fn submit_replace(
  state: text_kernel.TextState,
  start: Int,
  end: Int,
  value: String,
) -> #(text_kernel.TextState, Option(TextCommand)) {
  let assert Ok(#(state, _events, submission)) =
    text_kernel.replace_range(state, start, end, value)
  case submission {
    None -> #(state, None)
    Some(text_kernel.Submission(op, _message_id)) -> {
      let assert text_kernel.ReplaceRange(start, end, value, delta) = op
      #(state, Some(ReplaceRangeCmd(start, end, value, Some(delta))))
    }
  }
}

fn apply_remote(
  state: text_kernel.TextState,
  command: TextCommand,
  _meta: kernel_fuzz.SequencedMeta,
) -> Result(text_kernel.TextState, String) {
  let #(state, _events) =
    text_kernel.apply_remote(state, to_kernel_op(command, "apply_remote"))
  Ok(state)
}

fn ack_local(
  state: text_kernel.TextState,
  command: TextCommand,
  _meta: kernel_fuzz.SequencedMeta,
) -> Result(text_kernel.TextState, String) {
  case text_kernel.ack_local(state, to_kernel_op(command, "ack_local")) {
    Ok(state) -> Ok(state)
    Error(text_kernel.UnexpectedAck(detail))
    | Error(text_kernel.UnexpectedRollback(detail)) -> Error(detail)
  }
}

fn rollback(
  state: text_kernel.TextState,
  command: TextCommand,
) -> text_kernel.TextState {
  case list.last(state.pending) {
    Error(_) -> state
    Ok(text_kernel.PendingOp(_, message_id)) ->
      case
        text_kernel.rollback(
          state,
          to_kernel_op(command, "rollback"),
          message_id,
        )
      {
        Ok(#(state, _events)) -> state
        Error(_) -> state
      }
  }
}

fn apply_stashed(
  state: text_kernel.TextState,
  command: TextCommand,
  meta: kernel_fuzz.SubmitMeta,
) -> #(text_kernel.TextState, TextCommand) {
  case command {
    InsertCmd(_, _, Some(_))
    | DeleteRangeCmd(_, _, Some(_))
    | ReplaceRangeCmd(_, _, _, Some(_))
    | AppendCmd(_, Some(_)) -> {
      let #(state, _events, _op, _message_id) =
        text_kernel.apply_stashed_op(
          state,
          to_kernel_op(command, "apply_stashed"),
        )
      #(state, command)
    }
    InsertCmd(_, _, None)
    | DeleteRangeCmd(_, _, None)
    | ReplaceRangeCmd(_, _, _, None)
    | AppendCmd(_, None) ->
      case submit(state, command, meta) {
        #(state, Some(routed)) -> #(state, routed)
        #(state, None) -> {
          // The generated command happened to be a synchronous no-op
          // (empty insert/append, or a zero-length delete/replace range).
          // A stash always holds a previously-decided *real* edit, so fall
          // back to a guaranteed non-empty append rather than routing
          // nothing — `apply_stashed`'s signature always returns an op.
          let #(state, _events, submission) =
            text_kernel.append(state, fallback_value(1))
          let assert Some(text_kernel.Submission(op, _message_id)) = submission
          let assert text_kernel.Append(value, delta) = op
          #(state, AppendCmd(value, Some(delta)))
        }
      }
  }
}

fn load_from_synced(
  state: text_kernel.TextState,
  id: Int,
) -> text_kernel.TextState {
  let raw = json.to_string(text_kernel.summary(state))
  let assert Ok(loaded) =
    text_kernel.from_summary(
      raw,
      replica_id.new("client-" <> int.to_string(id)),
    )
  loaded
}

pub fn model() -> KernelModel(text_kernel.TextState, TextCommand, String) {
  KernelModel(
    name: "text",
    init: fn(id) {
      text_kernel.new(replica_id.new("client-" <> int.to_string(id)))
    },
    submit: submit,
    apply_remote: apply_remote,
    ack_local: ack_local,
    observe: text_kernel.value,
    gen_op: op_generator(),
    check: Some(text_kernel.check_cache_coherence),
    canonicalize: None,
    ack_preserves_view: True,
    op_to_json: op_to_json,
    op_decoder: op_decoder(),
    capabilities: Capabilities(
      load_from_synced: Some(load_from_synced),
      oracle: None,
      rollback: Some(rollback),
      resubmit: None,
      apply_stashed: Some(apply_stashed),
      react: None,
      remove_member: None,
    ),
  )
}
