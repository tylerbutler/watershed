// docs:snippet-start practice-pure-state
pub type State {
  State(current_generation: Int, pending: Bool)
}

// docs:snippet-end practice-pure-state

// docs:snippet-start practice-pure-idle
pub fn idle() -> State {
  State(current_generation: 0, pending: False)
}

// docs:snippet-end practice-pure-idle

// docs:snippet-start practice-pure-request
pub fn request(state: State) -> #(State, Int) {
  let generation = state.current_generation + 1

  #(State(current_generation: generation, pending: True), generation)
}

// docs:snippet-end practice-pure-request

// docs:snippet-start practice-pure-flush
pub fn flush(state: State, generation: Int) -> #(State, Bool) {
  case state.pending && state.current_generation == generation {
    True -> #(
      State(current_generation: state.current_generation, pending: False),
      True,
    )
    False -> #(state, False)
  }
}
// docs:snippet-end practice-pure-flush
