import startest/expect
import watershed/fluid_ids
import watershed/tree/change
import watershed/tree/history

fn session() -> fluid_ids.SessionId {
  let assert Ok(value) =
    fluid_ids.session_id("00000000-0000-4000-8000-000000000001")
  value
}

fn revision(suffix: String) -> fluid_ids.StableId {
  let assert Ok(value) =
    fluid_ids.stable_id("00000000-0000-4000-8000-0000000000" <> suffix)
  value
}

fn commit(revision: fluid_ids.StableId) -> history.Commit {
  let assert Ok(order) = change.identity_order([#(revision, -1)])
  let assert Ok(checked) =
    change.from_data(change.to_data(change.empty()), order)
  history.Commit(revision, session(), checked)
}

pub fn shared_tree_history_resubmit_rejects_duplicate_repairs_test() -> Nil {
  let pending = commit(revision("01"))
  let assert Ok(local) = history.append_local(history.new(session()), pending)
  history.resubmit(local.history, [
    #(pending.revision, []),
    #(pending.revision, []),
  ])
  |> expect.to_be_error
  history.pending(local.history) |> expect.to_equal([pending])
}

pub fn shared_tree_history_resubmit_rejects_extraneous_commit_test() -> Nil {
  let pending = commit(revision("01"))
  let assert Ok(local) = history.append_local(history.new(session()), pending)
  history.resubmit(local.history, [#(revision("02"), [])])
  |> expect.to_be_error
  history.pending(local.history) |> expect.to_equal([pending])
}
