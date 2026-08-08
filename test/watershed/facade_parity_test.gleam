//// Mechanical parity check across the three public facades.
////
//// The failure this exists to prevent is specific and has already happened
//// once: a sweep covered *one* axis of a kind, and got recorded as covering
//// all of them. "All 14 kinds have full typed-layer parity" was true for
//// channel lifecycle and false for operations, subscriptions, and runtime
//// semantics — and nothing mechanical could tell the difference, because
//// parity lived entirely in prose.
////
//// A kind is usable only when four axes hold:
////
////   1. lifecycle — create / ensure / resolve / handle / typed field pair
////   2. operations — the verbs that mutate and read it
////   3. subscription — how an app learns a peer changed something
////   4. runtime semantics — the wiring that implements the kernel's contract
////
//// Axes 1–3 are names, so this test checks them by name. Axis 4 is behaviour
//// and cannot be checked here — it is what the per-kind convergence and
//// integration tests are for. A kind can pass every assertion in this file and
//// still not do what its kernel promises; `PactMap` was exactly that case, with
//// a complete, well-named, fully-typed facade over a fabricated quorum.
////
//// This reads the facade sources as text rather than reflecting over exports,
//// because reflection is not available on both targets. Audit by full
//// inventory diff, never by prefix guess — a prefix grep is what once produced
//// a false "`ordered_*` is missing" report against a facade that had it.

import gleam/list
import gleam/set.{type Set}
import gleam/string
import simplifile
import startest/expect

/// One channel kind and the names each facade must expose for it.
type Kind {
  Kind(
    name: String,
    /// create / ensure / resolve / handle / typed field pair.
    lifecycle: List(String),
    /// The verbs that mutate or read the kind.
    ops: List(String),
    /// Change notification.
    subscribes: List(String),
  )
}

fn kinds() -> List(Kind) {
  [
    Kind(
      "map",
      [
        "create_map",
        "ensure_map",
        "resolve_map_field",
        "set_map_field",
        "handle_of",
        "resolve",
      ],
      ["set", "get", "delete", "has", "keys", "entries", "size", "clear"],
      ["subscribe"],
    ),
    Kind(
      "counter",
      [
        "create_counter",
        "ensure_counter",
        "resolve_counter",
        "resolve_counter_field",
        "set_counter_field",
        "counter_handle_of",
      ],
      ["increment", "counter_value"],
      ["subscribe_counter"],
    ),
    Kind(
      "pn_counter",
      [
        "create_pn_counter",
        "ensure_pn_counter",
        "resolve_pn_counter",
        "resolve_pn_counter_field",
        "set_pn_counter_field",
        "pn_counter_handle_of",
      ],
      ["pn_counter_update", "pn_counter_value"],
      ["subscribe_pn_counter"],
    ),
    Kind(
      "or_map",
      [
        "create_or_map",
        "ensure_or_map",
        "resolve_or_map",
        "resolve_or_map_field",
        "set_or_map_field",
        "or_map_handle_of",
      ],
      [
        "or_map_set",
        "or_map_set_json",
        "or_map_remove",
        "or_map_value",
        "or_map_keys",
        "or_map_entries",
        "or_map_increment",
      ],
      ["subscribe_or_map"],
    ),
    Kind(
      "or_set",
      [
        "create_or_set",
        "ensure_or_set",
        "resolve_or_set",
        "resolve_or_set_field",
        "set_or_set_field",
        "or_set_handle_of",
      ],
      ["or_set_add", "or_set_remove", "or_set_contains", "or_set_values"],
      ["subscribe_or_set"],
    ),
    Kind(
      "g_set",
      [
        "create_g_set",
        "ensure_g_set",
        "resolve_g_set",
        "resolve_g_set_field",
        "set_g_set_field",
        "g_set_handle_of",
      ],
      ["g_set_add", "g_set_contains", "g_set_values"],
      ["subscribe_g_set"],
    ),
    Kind(
      "two_p_set",
      [
        "create_two_p_set",
        "ensure_two_p_set",
        "resolve_two_p_set",
        "resolve_two_p_set_field",
        "set_two_p_set_field",
        "two_p_set_handle_of",
      ],
      [
        "two_p_set_add",
        "two_p_set_remove",
        "two_p_set_contains",
        "two_p_set_values",
      ],
      ["subscribe_two_p_set"],
    ),
    Kind(
      "register_collection",
      [
        "create_register_collection",
        "ensure_register_collection",
        "resolve_register_collection",
        "resolve_register_collection_field",
        "set_register_collection_field",
        "register_collection_handle_of",
      ],
      [
        "register_write",
        "register_read",
        "register_get",
        "register_keys",
        "register_versions",
      ],
      ["subscribe_register_collection"],
    ),
    Kind(
      "sequence",
      [
        "create_sequence",
        "ensure_sequence",
        "resolve_sequence",
        "resolve_sequence_field",
        "set_sequence_field",
        "sequence_handle_of",
      ],
      [
        "sequence_insert",
        "sequence_delete",
        "sequence_replace",
        "sequence_move",
        "sequence_values",
        "sequence_length",
      ],
      ["subscribe_sequence"],
    ),
    Kind(
      "text",
      [
        "create_text",
        "ensure_text",
        "resolve_text",
        "resolve_text_field",
        "set_text_field",
        "text_handle_of",
      ],
      [
        "text_insert",
        "text_append",
        "text_delete_range",
        "text_replace_range",
        "text_value",
        "text_length",
        "text_substring",
        "text_anchor_at",
        "text_resolve_anchor",
      ],
      ["subscribe_text"],
    ),
    Kind(
      "rich_text",
      [
        "create_rich_text",
        "ensure_rich_text",
        "resolve_rich_text",
        "resolve_rich_text_field",
        "set_rich_text_field",
        "rich_text_handle_of",
      ],
      ["submit_rich_text", "rich_text_view"],
      ["subscribe_rich_text"],
    ),
    Kind(
      "json_ot",
      [
        "create_json_ot",
        "ensure_json_ot",
        "resolve_json_ot",
        "resolve_json_ot_field",
        "set_json_ot_field",
        "json_ot_handle_of",
      ],
      ["submit_json_ot", "json_ot_view"],
      ["subscribe_json_ot"],
    ),
    Kind(
      "directory",
      [
        "create_directory",
        "ensure_directory",
        "resolve_directory",
        "resolve_directory_field",
        "set_directory_field",
        "directory_handle_of",
      ],
      [
        "directory_set",
        "directory_get",
        "directory_delete",
        "directory_entries",
        "directory_clear",
        "directory_subdirectories",
        "directory_create_subdirectory",
        "directory_delete_subdirectory",
        "directory_has_subdirectory",
      ],
      ["subscribe_directory"],
    ),
    Kind(
      "pact_map",
      [
        "create_pact_map",
        "ensure_pact_map",
        "resolve_pact_map",
        "resolve_pact_map_field",
        "set_pact_map_field",
        "pact_map_handle_of",
      ],
      [
        "pact_map_set",
        "pact_map_delete",
        "pact_map_get",
        "pact_map_keys",
        "pact_map_is_pending",
        "pact_map_pending",
        "pact_map_pending_signoffs",
        "pact_map_get_with_details",
      ],
      ["subscribe_pact_map"],
    ),
    Kind(
      "ordered_collection",
      [
        "create_ordered_collection",
        "ensure_ordered_collection",
        "resolve_ordered_collection",
        "resolve_ordered_collection_field",
        "set_ordered_collection_field",
        "ordered_collection_handle_of",
      ],
      [
        "ordered_add",
        "ordered_acquire",
        "ordered_complete",
        "ordered_release",
        "ordered_size",
      ],
      ["subscribe_ordered_collection"],
    ),
    Kind(
      "task_manager",
      [
        "create_task_manager",
        "ensure_task_manager",
        "resolve_task_manager",
        "resolve_task_manager_field",
        "set_task_manager_field",
        "task_manager_handle_of",
      ],
      [
        "volunteer_for_task",
        "abandon_task",
        "complete_task",
        "task_assigned",
        "task_queued",
        "task_queues",
      ],
      ["subscribe_task_manager"],
    ),
    Kind(
      "claims",
      [
        "create_claims",
        "ensure_claims",
        "resolve_claims",
        "resolve_claims_field",
        "set_claims_field",
        "claims_handle_of",
      ],
      ["try_set_claim", "get_claim", "has_claim", "compare_and_set_claim"],
      ["subscribe_claims"],
    ),
  ]
}

/// Names that legitimately exist on one facade only. Each is an escape hatch
/// into a target's own runtime representation, not a channel kind — so there is
/// nothing for the other facade to mirror.
const beam_only = ["runtime_subject"]

const js_only = ["runtime_of", "diagnostics"]

/// `watershed_lustre` wraps the callback-shaped surface (`ensure_*`,
/// `subscribe_*`) and nothing else; edits and reads stay on `watershed_js`.
/// Kinds it has not been given bindings for go here.
///
/// Empty is the invariant, and the test below is two-sided about it: a new kind
/// that reaches the facades without Lustre bindings fails, and so does closing a
/// gap without deleting its entry. Neither direction can rot into prose.
const lustre_gaps: List(String) = []

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

/// Every kind exposes every lifecycle, operation, and subscription name on the
/// BEAM facade.
pub fn beam_facade_covers_every_axis_test() {
  let exports = exports_of("src/watershed.gleam")
  missing_names(exports, kinds()) |> expect.to_equal([])
}

/// ...and the same on the JS facade. Kept as a separate test so a failure names
/// which target regressed.
pub fn js_facade_covers_every_axis_test() {
  let exports = exports_of("src/watershed_js.gleam")
  missing_names(exports, kinds()) |> expect.to_equal([])
}

/// The two facades expose the same surface, modulo the documented per-target
/// escape hatches. This is the check that would have caught `SharedRichText`
/// being absent from the JS facade for as long as it was.
pub fn facades_agree_with_each_other_test() {
  let beam = exports_of("src/watershed.gleam")
  let js = exports_of("src/watershed_js.gleam")

  set.difference(beam, js)
  |> set.difference(set.from_list(beam_only))
  |> sorted
  |> expect.to_equal([])

  set.difference(js, beam)
  |> set.difference(set.from_list(js_only))
  |> sorted
  |> expect.to_equal([])
}

/// `watershed_lustre` has an `ensure_*` and a `subscribe_*` for every kind
/// except the documented gaps — and the gap list names exactly those, so
/// closing one without updating the list fails here.
pub fn lustre_gaps_are_exactly_as_documented_test() {
  let exports = exports_of("watershed_lustre/src/watershed_lustre.gleam")
  let expected =
    kinds()
    |> list.flat_map(fn(kind) {
      list.append(lustre_ensure_names(kind), kind.subscribes)
    })

  expected
  |> list.filter(fn(name) { !set.contains(exports, name) })
  |> list.unique
  |> list.sort(string.compare)
  |> expect.to_equal(list.sort(lustre_gaps, string.compare))
}

/// A guard on this file itself: if the source were unreadable or the extraction
/// broke, every assertion above would pass vacuously against an empty set.
pub fn extraction_actually_finds_exports_test() {
  { set.size(exports_of("src/watershed.gleam")) > 100 } |> expect.to_be_true()
  { set.size(exports_of("src/watershed_js.gleam")) > 100 }
  |> expect.to_be_true()
  { set.size(exports_of("watershed_lustre/src/watershed_lustre.gleam")) > 20 }
  |> expect.to_be_true()
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

fn missing_names(exports: Set(String), kinds: List(Kind)) -> List(String) {
  kinds
  |> list.flat_map(fn(kind) {
    [kind.lifecycle, kind.ops, kind.subscribes]
    |> list.flatten
    |> list.filter(fn(name) { !set.contains(exports, name) })
    |> list.map(fn(name) { kind.name <> "." <> name })
  })
  |> list.sort(string.compare)
}

/// The `ensure_*` a Lustre binding would carry for this kind, derived from the
/// kind's own lifecycle list rather than re-spelled, so a renamed `ensure_*`
/// cannot drift out of sync with this table.
fn lustre_ensure_names(kind: Kind) -> List(String) {
  list.filter(kind.lifecycle, string.starts_with(_, "ensure_"))
}

/// Every `pub fn` name in a module, read from source. Reflection over exports
/// is not available on both targets, so this parses the declarations.
fn exports_of(path: String) -> Set(String) {
  let assert Ok(source) = simplifile.read(path)
  source
  |> string.split("\n")
  |> list.filter_map(fn(line) {
    case string.starts_with(line, "pub fn ") {
      False -> Error(Nil)
      True ->
        line
        |> string.drop_start(string.length("pub fn "))
        |> string.split("(")
        |> list.first
    }
  })
  |> list.map(string.trim)
  |> list.filter(fn(name) { name != "" })
  |> set.from_list
}

fn sorted(names: Set(String)) -> List(String) {
  names |> set.to_list |> list.sort(string.compare)
}
