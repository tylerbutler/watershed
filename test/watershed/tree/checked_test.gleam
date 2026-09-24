pub fn value(value: Result(a, error)) -> a {
  let assert Ok(value) = value
  value
}
