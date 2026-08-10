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

pub fn remove_action_available(
  two_phase_present: Bool,
  observed_present: Bool,
) -> Bool {
  two_phase_present || observed_present
}

pub fn remove_action_label(
  item: String,
  two_phase_present: Bool,
  observed_present: Bool,
) -> String {
  case two_phase_present, observed_present {
    True, True ->
      "Remove " <> item <> " from TwoPSet and OrSet. GSet retains it."
    True, False ->
      "Remove "
      <> item
      <> " from TwoPSet. OrSet is already absent; GSet retains it."
    False, True ->
      "Remove "
      <> item
      <> " from OrSet. TwoPSet is already absent; GSet retains it."
    False, False ->
      "Remove unavailable for "
      <> item
      <> " — already absent from TwoPSet and OrSet. GSet still retains it."
  }
}

pub fn remove_action_text(
  two_phase_present: Bool,
  observed_present: Bool,
) -> String {
  case two_phase_present, observed_present {
    True, True -> "Remove from TwoPSet + OrSet"
    True, False -> "Remove from TwoPSet"
    False, True -> "Remove from OrSet"
    False, False -> "Remove unavailable"
  }
}

pub fn remove_feedback(
  item: String,
  two_phase_present: Bool,
  observed_present: Bool,
) -> Feedback {
  case two_phase_present, observed_present {
    True, True ->
      info(
        "Removed \""
        <> item
        <> "\" from TwoPSet and OrSet. GSet retained it because removal is not expressible.",
      )
    True, False ->
      info(
        "Removed \""
        <> item
        <> "\" from TwoPSet while OrSet was already absent. GSet retained it because removal is not expressible.",
      )
    False, True ->
      info(
        "Removed \""
        <> item
        <> "\" from OrSet while TwoPSet was already absent. GSet retained it because removal is not expressible.",
      )
    False, False ->
      warning(
        "Nothing removed for \""
        <> item
        <> "\" because it is already absent from TwoPSet and OrSet. GSet retained it because removal is not expressible.",
      )
  }
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
