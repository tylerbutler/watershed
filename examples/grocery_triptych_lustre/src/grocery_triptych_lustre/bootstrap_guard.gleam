import gleam/option.{type Option, None, Some}

pub fn failure_latched(error: Option(String)) -> Bool {
  case error {
    Some(_) -> True
    None -> False
  }
}
