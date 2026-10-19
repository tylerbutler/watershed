import gleam/option.{type Option, None, Some}

pub type Input {
  Input(
    value: String,
    composing: Bool,
    composition_end: Option(String),
    selection: Option(#(Int, Int)),
    canceled: Bool,
  )
}

pub type Transition {
  Transition(input: Input, publish: Option(String))
}

pub fn new(value: String) -> Input {
  Input(value, False, None, None, False)
}

pub fn remote(input: Input, value: String) -> Input {
  Input(..input, value: value)
}

pub fn changed(input: Input, value: String) -> Transition {
  case input.canceled, input.composing {
    True, _ -> Transition(input, None)
    False, True -> Transition(Input(..input, value: value), None)
    False, False ->
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
  Input(..input, composing: True, composition_end: None, canceled: False)
}

pub fn composition_ended(input: Input, value: String) -> Transition {
  case input.composing && !input.canceled {
    False -> Transition(Input(..input, canceled: True), None)
    True ->
      Transition(
        Input(
          ..input,
          value: value,
          composing: False,
          composition_end: Some(value),
        ),
        Some(value),
      )
  }
}

pub fn cancel(input: Input, value: String) -> Input {
  Input(
    ..input,
    value:,
    composing: False,
    canceled: input.canceled || input.composing,
    composition_end: None,
  )
}

pub fn interacted(input: Input) -> Input {
  Input(..input, canceled: False, composition_end: None)
}

pub fn selected(input: Input, start: Int, end: Int) -> Input {
  Input(..input, selection: Some(#(start, end)))
}
