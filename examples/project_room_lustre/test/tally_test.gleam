import gleam/dynamic/decode
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleeunit/should

import watershed
import watershed/component
import watershed/sluice_js
import watershed/transport_js

import project_room_lustre/tally

type Root

fn new_subtree(
  name: String,
) -> #(watershed.Document(Root), watershed.SharedMap) {
  let #(_, document, subtree) = new_sluice_subtree(name)
  #(document, subtree)
}

fn new_sluice_subtree(
  name: String,
) -> #(sluice_js.Sluice, watershed.Document(Root), watershed.SharedMap) {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let document = sluice_js.connect(sluice, "user-a")
  sluice_js.settle(sluice)
  let assert Ok(subtree) = watershed.create_map(document)
  #(sluice, document, subtree)
}

fn start(
  document: watershed.Document(Root),
  subtree: watershed.SharedMap,
  emitter: component.OutputEmitter,
) -> tally.Running {
  let outcome = transport_js.new_cell(None)
  tally.start(
    document,
    subtree,
    fn() { Nil },
    emitter,
    tally.Config(title: "Completions", target: 10),
    fn(result) { transport_js.set_cell(outcome, Some(result)) },
  )
  let assert Some(Ok(running)) = transport_js.get_cell(outcome)
  running
}

pub fn config_requires_a_positive_target_test() -> Nil {
  let invalid =
    tally.Config(title: "Completions", target: 0)
    |> tally.encode_config
  json.parse(json.to_string(invalid), tally.config_decoder())
  |> result.is_error
  |> should.be_true
}

pub fn add_updates_the_counter_test() -> Nil {
  let #(document, subtree) = new_subtree("tally-add")
  let running =
    start(document, subtree, component.output_emitter(fn(_) { Nil }))
  let assert Ok(#(running, [])) = tally.add(running, 3)
  tally.value(running) |> should.equal(3)
  let assert Ok(#(running, [])) = tally.add(running, -1)
  tally.value(running) |> should.equal(2)
}

pub fn add_rejects_zero_test() -> Nil {
  let #(document, subtree) = new_subtree("tally-zero")
  let running =
    start(document, subtree, component.output_emitter(fn(_) { Nil }))
  tally.add(running, 0)
  |> should.equal(Error("tally delta must not be zero"))
}

pub fn target_emits_once_test() -> promise.Promise(Nil) {
  let #(sluice, document, subtree) = new_sluice_subtree("tally-target")
  let published = transport_js.new_cell([])
  let emitter =
    component.output_emitter(fn(events) {
      transport_js.set_cell(published, [
        events,
        ..transport_js.get_cell(published)
      ])
    })
  let running = start(document, subtree, emitter)
  let assert Ok(#(running, [])) = tally.add(running, 10)
  tally.pending_target(running) |> should.be_true
  settle_runtime(sluice)
  promise.map(promise.resolve(Nil), fn(_) {
    tally.target_reached(running) |> should.be_true
    let events = transport_js.get_cell(published) |> list.flatten
    list.length(events) |> should.equal(1)
    let assert [event] = events
    component.output_id(event) |> should.equal("target_reached")
    json.parse(json.to_string(component.output_payload(event)), decode.int)
    |> should.equal(Ok(10))
    let assert Ok(#(_, [])) = tally.add(running, 1)
    settle_runtime(sluice)
    transport_js.get_cell(published)
    |> list.flatten
    |> list.length
    |> should.equal(1)
  })
}

pub fn concurrent_adds_converge_and_emit_once_test() -> promise.Promise(Nil) {
  let sluice = sluice_js.start(tenant: "default", document: "tally-convergence")
  let document_a = sluice_js.connect(sluice, "user-a")
  let document_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let assert Ok(subtree_a) = watershed.create_map(document_a)
  tally.initialize(document_a, subtree_a) |> should.equal(Ok(Nil))
  watershed.set(
    watershed.root(document_a),
    "shared",
    watershed.handle_of(subtree_a),
  )
  sluice_js.settle(sluice)
  let assert Ok(handle) = watershed.get(watershed.root(document_b), "shared")
  let assert Ok(subtree_b) = watershed.resolve(document_b, handle)

  let published_a = transport_js.new_cell([])
  let published_b = transport_js.new_cell([])
  let running_a =
    start(
      document_a,
      subtree_a,
      component.output_emitter(fn(events) {
        transport_js.set_cell(published_a, [
          events,
          ..transport_js.get_cell(published_a)
        ])
      }),
    )
  let running_b =
    start(
      document_b,
      subtree_b,
      component.output_emitter(fn(events) {
        transport_js.set_cell(published_b, [
          events,
          ..transport_js.get_cell(published_b)
        ])
      }),
    )

  sluice_js.pause(sluice, document_a)
  sluice_js.pause(sluice, document_b)
  let assert Ok(#(running_a, [])) = tally.add(running_a, 7)
  let assert Ok(#(running_b, [])) = tally.add(running_b, 5)
  sluice_js.resume(sluice, document_a)
  sluice_js.resume(sluice, document_b)
  settle_runtime(sluice)

  promise.map(promise.resolve(Nil), fn(_) {
    tally.value(running_a) |> should.equal(12)
    tally.value(running_b) |> should.equal(12)
    let published =
      list.append(
        transport_js.get_cell(published_a),
        transport_js.get_cell(published_b),
      )
      |> list.flatten
    list.length(published) |> should.equal(1)
  })
}

fn settle_runtime(sluice: sluice_js.Sluice) -> Nil {
  settle_rounds(sluice, 8)
}

fn settle_rounds(sluice: sluice_js.Sluice, remaining: Int) -> Nil {
  case remaining {
    0 -> Nil
    _ -> {
      sluice_js.advance(sluice, 0)
      sluice_js.settle(sluice)
      sluice_js.advance(sluice, 200)
      settle_rounds(sluice, remaining - 1)
    }
  }
}
