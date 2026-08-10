import gleam/string

import grocery_triptych_lustre/bootstrap_guard.{type Feedback, info, warning}

pub fn has_submittable_item(raw: String) -> Bool {
  case normalize_item_input(raw) {
    Ok(_) -> True
    Error(_) -> False
  }
}

pub fn normalize_item_input(raw: String) -> Result(String, String) {
  let item = string.trim(raw)

  case item {
    "" -> Error("Enter an item before adding to all three sets.")
    _ -> Ok(item)
  }
}

pub fn add_feedback(
  item: String,
  two_phase_was_present: Bool,
  two_phase_is_present: Bool,
) -> Feedback {
  case two_phase_was_present, two_phase_is_present {
    False, False ->
      warning(
        "TwoPSet ignored the re-add for \""
        <> item
        <> "\" because the item is tombstoned.",
      )

    _, _ -> info("Added \"" <> item <> "\" to all three sets.")
  }
}

pub fn remove_feedback(item: String) -> Feedback {
  info(
    "Removed \""
    <> item
    <> "\" from TwoPSet and OrSet. GSet retained it because removal is not expressible.",
  )
}

pub fn not_ready_feedback(action: String) -> Feedback {
  info(
    "Wait for the connection and pantry bootstrap to finish before "
    <> action
    <> ".",
  )
}

pub fn scenario_placeholder_feedback(name: String) -> Feedback {
  info(name <> " automation lands in the next task.")
}
