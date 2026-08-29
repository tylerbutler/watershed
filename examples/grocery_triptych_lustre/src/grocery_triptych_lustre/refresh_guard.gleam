pub type State {
  State(current_generation: Int, pending: Bool)
}

pub fn idle() -> State {
  State(current_generation: 0, pending: False)
}

pub fn request(state: State) -> #(State, Int) {
  let generation = state.current_generation + 1

  #(State(current_generation: generation, pending: True), generation)
}

pub fn flush(state: State, generation: Int) -> #(State, Bool) {
  case state.pending && state.current_generation == generation {
    True -> #(
      State(current_generation: state.current_generation, pending: False),
      True,
    )
    False -> #(state, False)
  }
}
