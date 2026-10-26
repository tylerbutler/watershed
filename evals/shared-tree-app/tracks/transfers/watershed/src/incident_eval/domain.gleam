import gleam/option.{type Option}

pub type Status {
  Open
  Investigating
  Resolved
}

pub type Step {
  Step(id: String, label: String, done: Bool)
}

pub type Incident {
  Incident(
    id: String,
    title: String,
    status: Status,
    assignee: Option(String),
    steps: List(Step),
  )
}

pub type Board {
  Board(incidents: List(Incident))
}

pub type Phase {
  Opening
  Ready
  Disconnected
  Closed
  Failed
}

pub type State {
  State(
    phase: Phase,
    document_id: Option(String),
    board: Board,
    errors: List(String),
  )
}

pub type Config {
  Config(
    base_url: String,
    socket_url: String,
    tenant: String,
    development_secret: String,
    document_id: Option(String),
    client_id: String,
  )
}

pub type Action {
  AddIncident(id: String, title: String)
  Title(id: String, value: String)
  Status(id: String, value: Status)
  Assignee(id: String, value: Option(String))
  RemoveIncident(id: String)
  MoveIncident(id: String, before: Option(String))
  AddStep(incident: String, id: String, label: String)
  StepLabel(incident: String, id: String, value: String)
  StepDone(incident: String, id: String, value: Bool)
  RemoveStep(incident: String, id: String)
  MoveStep(incident: String, id: String, before: Option(String))
  TransferStep(
    incident: String,
    id: String,
    destination: String,
    before: Option(String),
  )
}

pub fn phase_name(phase: Phase) -> String {
  case phase {
    Opening -> "opening"
    Ready -> "ready"
    Disconnected -> "disconnected"
    Closed -> "closed"
    Failed -> "error"
  }
}

pub fn status_name(status: Status) -> String {
  case status {
    Open -> "open"
    Investigating -> "investigating"
    Resolved -> "resolved"
  }
}
