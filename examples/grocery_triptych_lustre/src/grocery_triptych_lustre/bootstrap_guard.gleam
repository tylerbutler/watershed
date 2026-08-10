import gleam/option.{type Option, None, Some}

pub type FeedbackKind {
  Info
  Warning
}

pub type Feedback {
  Feedback(kind: FeedbackKind, message: String)
}

pub fn failure_latched(error: Option(String)) -> Bool {
  case error {
    Some(_) -> True
    None -> False
  }
}

pub fn success_feedback(
  error: Option(String),
  current: Option(Feedback),
  message: String,
) -> Option(Feedback) {
  case error {
    Some(_) -> current
    None -> Some(info(message))
  }
}

pub fn info(message: String) -> Feedback {
  Feedback(kind: Info, message: message)
}

pub fn warning(message: String) -> Feedback {
  Feedback(kind: Warning, message: message)
}
