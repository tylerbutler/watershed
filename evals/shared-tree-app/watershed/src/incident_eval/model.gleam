import gleam/option.{type Option, None}
import incident_eval/domain
import lustre/effect.{type Effect}
import watershed
import watershed/tree

pub opaque type Model {
  Model(state: domain.State)
}

pub opaque type Msg {
  Unimplemented
}

pub fn init(_config: domain.Config) -> #(Model, Effect(Msg)) {
  #(
    Model(
      domain.State(domain.Failed, None, domain.Board([]), ["Not implemented"]),
    ),
    effect.none(),
  )
}

pub fn update(model: Model, _message: Msg) -> #(Model, Effect(Msg)) {
  #(model, effect.none())
}

pub fn apply(model: Model, _action: domain.Action) -> #(Model, Effect(Msg)) {
  #(model, effect.none())
}

pub fn close(model: Model) -> #(Model, Effect(Msg)) {
  #(Model(domain.State(..model.state, phase: domain.Closed)), effect.none())
}

pub fn read(model: Model) -> domain.State {
  model.state
}

pub fn native_tree(_model: Model) -> Option(tree.Tree(domain.Board)) {
  None
}

pub fn native_document(_model: Model) -> Option(watershed.Document(Nil)) {
  None
}
