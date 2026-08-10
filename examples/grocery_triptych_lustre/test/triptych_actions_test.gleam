import gleeunit
import gleeunit/should

import grocery_triptych_lustre/bootstrap_guard
import triptych_actions

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn normalize_item_input_trims_without_touching_case_test() {
  triptych_actions.normalize_item_input("  Whole Milk  ")
  |> should.equal(Ok("Whole Milk"))
}

pub fn normalize_item_input_rejects_whitespace_only_test() {
  triptych_actions.normalize_item_input("   \n\t  ")
  |> should.equal(Error("Enter an item before adding to all three sets."))
}

pub fn tombstoned_two_p_set_readd_reports_a_warning_test() {
  triptych_actions.add_feedback("milk", False, False)
  |> should.equal(bootstrap_guard.warning(
    "TwoPSet ignored the re-add for \"milk\" because the item is tombstoned.",
  ))
}

pub fn normal_add_reports_success_test() {
  triptych_actions.add_feedback("milk", False, True)
  |> should.equal(bootstrap_guard.info("Added \"milk\" to all three sets."))
}
