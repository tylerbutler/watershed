import gleam/list

pub type Endpoint {
  Replica(String)
  Sequencer
}

pub type Flow {
  Flow(id: Int, from: Endpoint, to: Endpoint, label: String)
}

pub fn add(flows: List(Flow), added: Flow) -> List(Flow) {
  list.append(flows, [added])
}

pub fn remove(flows: List(Flow), id: Int) -> List(Flow) {
  list.filter(flows, fn(item) { item.id != id })
}

pub fn in_flight(flows: List(Flow)) -> Int {
  list.length(flows)
}
