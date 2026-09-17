import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import watershed_site/sudoku/runtime as sudoku

pub fn static_and_ready_state_test() {
  let static = sudoku.static_model()
  static.phase |> should.equal(sudoku.Static)
  static.rig |> should.equal(None)
  static.error |> should.equal(None)
  static.boards |> should.equal([])
  sudoku.init().0.phase |> should.equal(sudoku.Starting)

  let assert Ok(rig) = sudoku.start_rig()
  let ready = sudoku.update(sudoku.init().0, sudoku.Started(0, Ok(rig))).0
  ready.phase |> should.equal(sudoku.Ready)
  ready.converged |> should.be_true()
  ready.boards |> list.length |> should.equal(3)
  ready.boards
  |> list.each(fn(board) {
    board.cells |> list.length |> should.equal(81)
    board.cells |> list.all(fn(value) { value == None }) |> should.be_true()
  })
}

pub fn real_cell_write_diverges_and_converges_test() {
  let assert Ok(rig) = sudoku.start_rig()
  let ready = sudoku.update(sudoku.init().0, sudoku.Started(0, Ok(rig))).0
  let assert Ok(mutation) = sudoku.submit_set(rig, sudoku.ClientA, 0, 0, 5)
  let pending =
    sudoku.update(ready, sudoku.MutationSubmitted(0, Ok(mutation))).0
  sudoku.cell(pending, sudoku.ClientA, 0, 0) |> should.equal(Some(5))
  sudoku.cell(pending, sudoku.ClientB, 0, 0) |> should.equal(None)
  pending.pending |> list.length |> should.equal(1)
  pending.converged |> should.be_false()

  let assert Ok(delivery) = sudoku.deliver_group(rig)
  let complete = sudoku.update(pending, sudoku.Delivered(0, Ok(delivery))).0
  [sudoku.ClientA, sudoku.ClientB, sudoku.ClientC]
  |> list.each(fn(replica) {
    sudoku.cell(complete, replica, 0, 0) |> should.equal(Some(5))
  })
  complete.pending |> should.equal([])
  complete.converged |> should.be_true()
  { complete.latest_sequence > 0 } |> should.be_true()
}

pub fn same_cell_race_converges_on_last_sequenced_value_test() {
  let assert Ok(rig) = sudoku.start_rig()
  let ready = sudoku.update(sudoku.init().0, sudoku.Started(0, Ok(rig))).0
  let assert Ok(mutation) = sudoku.submit_race(rig)
  mutation.pending |> list.length |> should.equal(3)
  let pending =
    sudoku.update(ready, sudoku.MutationSubmitted(0, Ok(mutation))).0
  sudoku.cell(pending, sudoku.ClientA, 4, 4) |> should.equal(Some(1))
  sudoku.cell(pending, sudoku.ClientB, 4, 4) |> should.equal(Some(5))
  sudoku.cell(pending, sudoku.ClientC, 4, 4) |> should.equal(Some(9))

  let complete =
    list.fold([1, 2, 3], pending, fn(model, _) {
      let assert Ok(delivery) = sudoku.deliver_group(rig)
      sudoku.update(model, sudoku.Delivered(0, Ok(delivery))).0
    })
  [sudoku.ClientA, sudoku.ClientB, sudoku.ClientC]
  |> list.each(fn(replica) {
    sudoku.cell(complete, replica, 4, 4) |> should.equal(Some(9))
  })
  complete.converged |> should.be_true()
  complete.log |> list.length |> should.equal(3)
}

pub fn reset_and_stale_messages_test() {
  let assert Ok(rig) = sudoku.start_rig()
  let ready = sudoku.update(sudoku.init().0, sudoku.Started(0, Ok(rig))).0
  let reset = sudoku.update(ready, sudoku.Reset).0
  reset.generation |> should.equal(1)
  reset.phase |> should.equal(sudoku.Starting)
  [
    sudoku.Started(0, Ok(rig)),
    sudoku.ResetDone(0, Ok(rig)),
    sudoku.MutationSubmitted(0, Error(sudoku.UnexpectedDelivery("old"))),
    sudoku.Delivered(0, Error(sudoku.UnexpectedDelivery("old"))),
    sudoku.Deliver(0),
    sudoku.ClearFlow(0, 1),
  ]
  |> list.each(fn(message) {
    sudoku.update(reset, message).0 |> should.equal(reset)
  })
}

pub fn invalid_cells_fail_without_writing_test() {
  let assert Ok(rig) = sudoku.start_rig()
  sudoku.submit_set(rig, sudoku.ClientA, -1, 0, 5)
  |> should.equal(Error(sudoku.InvalidCell(-1, 0)))
  sudoku.submit_set(rig, sudoku.ClientA, 0, 0, 10)
  |> should.equal(Error(sudoku.InvalidDigit(10)))
}
