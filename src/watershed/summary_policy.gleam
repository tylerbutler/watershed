//// When a client must summarize the document without a request.
////
//// A document collects operations without a limit. A client that joins replays
//// every operation, unless a summary exists to start from. `summarize` can
//// always write that checkpoint. This module is the policy that decides when
//// to write it, so an application does not have to decide.
////
//// **The procedure: threshold, then delay, then a second check.** The runtime
//// counts the messages that sequence after the last known checkpoint. When
//// that count is more than `threshold`, and the client is settled (see
//// `runtime_core.wants_summary`), the runtime waits. The length of the wait
//// comes from the client id, so it differs for each client. The runtime then
//// asks again.
////
//// The delay keeps the cost of a room low. Every client crosses the threshold
//// on the same message, but the room receives an announcement of a summary.
//// The first summary that sequences advances the checkpoint of every other
//// client, and their second check thus does nothing. A lost race costs one
//// unnecessary upload. It never produces an incorrect document.
////
//// **The unit is sequenced messages, not edits.** A server sequences a batch
//// of submitted operations as one message. A burst of edits thus moves the
//// count much less than the number of edits. Messages are the correct unit,
//// because a client that joins replays messages. But a threshold that you
//// choose by counting single edits is much too high.
////
//// **A summary needs traffic.** The check runs when a message sequences. A
//// document that becomes quiet immediately after the threshold stays at that
//// count until the next edit. That edit causes the summary. Nothing is lost
//// before it.
////
//// **The policy is off unless you ask for it.** `watershed.auto_summarize`
//// installs a policy on a connected document. Without a policy, nothing
//// summarizes, which is the behaviour of every existing application.

/// A summarization policy. It sets how far a document can drift past the last
/// checkpoint, and how wide the window is that the room spreads its attempts
/// over.
pub opaque type Policy {
  Policy(threshold: Int, jitter_milliseconds: Int)
}

/// The default policy. It summarizes after 500 operations sequence past the
/// last checkpoint, and it spreads the attempts across a 3 second window.
///
/// The threshold is conservative on purpose. A threshold that is too high makes
/// a client that joins replay a long tail. A threshold that is too low makes a
/// busy document write many blobs, and each blob is a full snapshot of every
/// channel. 500 is less than the 1000-message in-band history window of
/// floodgate, so the catch-up of a client that joins stays in band. The count
/// is in sequenced messages, so it is much more than 500 edits.
///
/// Keep the threshold much more than 1. The summarize operation of a client is
/// itself a sequenced message, so the drift becomes 1 after a checkpoint, and
/// not 0. A threshold of 1 would thus trigger again on its own announcement,
/// without an end.
pub fn policy() -> Policy {
  Policy(threshold: 500, jitter_milliseconds: 3000)
}

/// The number of operations past the checkpoint before the client attempts a
/// summary.
pub fn with_threshold(policy: Policy, threshold: Int) -> Policy {
  Policy(..policy, threshold: threshold)
}

/// The window that the attempts spread across. A value of zero starts the
/// attempt immediately. A test with one client needs that value. A room with
/// many clients does not.
pub fn with_jitter_milliseconds(
  policy: Policy,
  jitter_milliseconds: Int,
) -> Policy {
  Policy(..policy, jitter_milliseconds: jitter_milliseconds)
}

pub fn policy_threshold(policy: Policy) -> Int {
  policy.threshold
}

pub fn policy_jitter_milliseconds(policy: Policy) -> Int {
  policy.jitter_milliseconds
}
