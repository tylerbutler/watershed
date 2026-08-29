import gleeunit
import gleeunit/should

import grocery_triptych_lustre/bootstrap_guard
import grocery_triptych_lustre/triptych_action

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn normalize_item_input_trims_without_touching_case_test() -> Nil {
  triptych_action.normalize_item_input("  Whole Milk  ")
  |> should.equal(Ok("Whole Milk"))
}

pub fn normalize_item_input_rejects_whitespace_only_test() -> Nil {
  triptych_action.normalize_item_input("   \n\t  ")
  |> should.equal(Error("Enter an item before adding to all three sets."))
}

pub fn has_submittable_item_trims_whitespace_test() -> Nil {
  triptych_action.has_submittable_item("  oranges  ")
  |> should.equal(True)
}

pub fn tombstoned_two_p_set_readd_reports_a_warning_test() -> Nil {
  triptych_action.add_feedback("milk", False, False)
  |> should.equal(bootstrap_guard.warning(
    "TwoPSet ignored the re-add for \"milk\" because the item is tombstoned.",
  ))
}

pub fn normal_add_reports_success_test() -> Nil {
  triptych_action.add_feedback("milk", False, True)
  |> should.equal(bootstrap_guard.info("Added \"milk\" to all three sets."))
}

pub fn remove_action_available_tracks_either_removable_set_test() -> Nil {
  triptych_action.remove_action_available(False, True)
  |> should.equal(True)

  triptych_action.remove_action_available(False, False)
  |> should.equal(False)
}

pub fn remove_action_text_names_the_remaining_set_test() -> Nil {
  triptych_action.remove_action_text(False, True)
  |> should.equal("Remove from OrSet")
}

pub fn remove_action_label_calls_out_single_set_removal_test() -> Nil {
  triptych_action.remove_action_label("milk", True, False)
  |> should.equal(
    "Remove milk from TwoPSet. OrSet is already absent; GSet retains it.",
  )
}

pub fn remove_absent_item_reports_warning_test() -> Nil {
  triptych_action.remove_feedback("milk", False, False)
  |> should.equal(bootstrap_guard.warning(
    "Nothing removed for \"milk\" because it is already absent from TwoPSet and OrSet. GSet retained it because removal is not expressible.",
  ))
}

pub fn remove_present_item_reports_success_test() -> Nil {
  triptych_action.remove_feedback("milk", True, True)
  |> should.equal(bootstrap_guard.info(
    "Removed \"milk\" from TwoPSet and OrSet. GSet retained it because removal is not expressible.",
  ))
}

pub fn remove_single_set_reports_the_other_as_already_absent_test() -> Nil {
  triptych_action.remove_feedback("milk", False, True)
  |> should.equal(bootstrap_guard.info(
    "Removed \"milk\" from OrSet while TwoPSet was already absent. GSet retained it because removal is not expressible.",
  ))
}
