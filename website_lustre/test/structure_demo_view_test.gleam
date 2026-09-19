import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/element
import watershed/pact_map_kernel
import watershed_site/structure_demo/model.{
  ClientA, Map, Model, MvRegister, PactMap, PactReplica,
}
import watershed_site/structure_demo/runtime
import watershed_site/structure_demo/view

pub fn static_map_exposes_the_shared_demo_contract_test() {
  let html =
    view.static(Map, view.Options(False, ["map"], None))
    |> element.to_string
  [
    "data-demo-rig",
    "data-dds=\"map\"",
    "data-client=\"a\"",
    "data-step=\"1\"",
    "data-race",
    "data-reset",
  ]
  |> contains_all(html)
}

pub fn interactive_mv_register_uses_lustre_handlers_test() {
  let html =
    view.static(MvRegister, view.Options(True, ["mv-register"], None))
    |> element.to_string
  [
    "data-mv-register-input",
    "data-mv-register-write",
    "data-mv-register-resolve",
    "data-cut-link",
    "data-replay",
  ]
  |> contains_all(html)
}

pub fn mv_register_renders_current_draft_and_submit_controls_test() {
  let model = runtime.ready_model(MvRegister)
  let #(model, _) =
    runtime.update(model, runtime.SetDraft(ClientA, "typed revision"))
  let html =
    view.view(model, view.Options(True, ["mv-register"], None))
    |> element.to_string
  [
    "value=\"typed revision\"",
    "data-mv-register-write",
    "data-mv-register-submit",
  ]
  |> contains_all(html)
}

pub fn visible_error_is_rendered_independently_of_link_state_test() {
  let model = runtime.ready_model(Map)
  let model = runtime.transition(model, runtime.ToggleLink)
  let #(model, _) =
    runtime.update(model, runtime.RuntimeFailed("projection failed"))
  let html =
    view.view(model, view.Options(False, ["map"], None))
    |> element.to_string
  [
    "role=\"alert\"",
    "projection failed",
    "Restore link",
    "aria-pressed=\"true\"",
  ]
  |> contains_all(html)
}

pub fn pact_view_names_the_remaining_signer_test() {
  let model =
    Model(
      ..runtime.ready_model(PactMap),
      alpha: PactReplica(
        pact_map_kernel.from_summary([
          #(
            "gate-policy",
            pact_map_kernel.Pact(
              None,
              Some(pact_map_kernel.Pending(Some(json.string("Survey")), [2])),
            ),
          ),
        ]),
      ),
    )
  let html =
    view.view(model, view.Options(False, ["pact"], Some("PactMap")))
    |> element.to_string
  ["awaiting B"] |> contains_all(html)
}

fn contains_all(expected: List(String), html: String) {
  list.each(expected, fn(fragment) {
    let assert True = string.contains(html, fragment) as fragment
  })
}
