import gleam/option.{type Option, None, Some}

pub type Input {
  Input(
    value: String,
    composing: Bool,
    composition_end: Option(String),
    selection: Option(#(Int, Int)),
  )
}

pub type Transition {
  Transition(input: Input, publish: Option(String))
}

pub fn new(value: String) -> Input {
  Input(value, False, None, None)
}

pub fn remote(input: Input, value: String) -> Input {
  Input(..input, value: value)
}

pub fn changed(input: Input, value: String) -> Transition {
  case input.composing {
    True -> Transition(Input(..input, value: value), None)
    False ->
      Transition(
        Input(..input, value: value, composition_end: None),
        case input.composition_end == Some(value) {
          True -> None
          False -> Some(value)
        },
      )
  }
}

pub fn composition_started(input: Input) -> Input {
  Input(..input, composing: True, composition_end: None)
}

pub fn composition_ended(input: Input, value: String) -> Transition {
  Transition(
    Input(..input, value: value, composing: False, composition_end: Some(value)),
    Some(value),
  )
}

pub fn selected(input: Input, start: Int, end: Int) -> Input {
  Input(..input, selection: Some(#(start, end)))
}
