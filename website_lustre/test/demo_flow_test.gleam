import gleeunit/should
import watershed_site/demo/flow

pub fn removing_one_flow_keeps_the_other_test() {
  let first = flow.Flow(1, flow.Replica("a"), flow.Sequencer, "set")
  let second = flow.Flow(2, flow.Sequencer, flow.Replica("b"), "deliver")
  [first, second]
  |> flow.remove(1)
  |> should.equal([second])
}

pub fn adding_flows_preserves_order_and_updates_count_test() {
  let first = flow.Flow(1, flow.Replica("a"), flow.Sequencer, "set")
  let second = flow.Flow(2, flow.Sequencer, flow.Replica("b"), "deliver")
  let flows = [] |> flow.add(first) |> flow.add(second)

  flows |> should.equal([first, second])
  flows |> flow.in_flight |> should.equal(2)
}
