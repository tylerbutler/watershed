//// When a client must summarize the document without a request.
////
//// A document collects operations without a limit. A client that joins replays
//// every operation, unless a summary exists to start from. `summarize` can
//// always write that checkpoint. This module is the policy that decides when
//// to write it, so an application does not have to decide.
////
//// **The procedure: threshold, then delay, then a second check.** The runtime
//// counts the messages that sequence after the last known checkpoint. When
//// that count reaches `threshold`, and the client is settled (see
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
//// **A summary needs traffic to schedule an attempt.** The check runs when a
//// message sequences. A scheduled attempt can run while the room is quiet.
//// If it fails or the client is no longer settled, another sequenced message
//// is needed to schedule the next attempt.
////
//// **The policy is enabled by default on both runtimes.**
//// `watershed.auto_summarize` and `watershed_beam.auto_summarize` replace the
//// policy on a connected document. Their `stop_auto_summarize` functions
//// disable it for that client. Uploads require floodgate summary storage and
//// a token with the `summary:write` scope.

/// A summarization policy. It sets the number of messages that triggers an
/// attempt and the delay window for the clients in a room.
pub opaque type Policy {
  Policy(threshold: Int, jitter_milliseconds: Int)
}

/// The default policy. It attempts a summary after 500 messages sequence past
/// the last checkpoint. It spreads the attempts across a 3 second window.
///
/// The threshold is conservative on purpose. A threshold that is too high makes
/// a client that joins replay a long tail. A threshold that is too low makes a
/// busy document write many blobs, and each blob is a full snapshot of every
/// channel. 500 is less than the 1000-message in-band history window of
/// floodgate. This leaves room for messages during the delay and upload, but
/// does not guarantee an in-band catch-up. Failures and clients that are not
/// settled can also extend the history. A message can contain multiple edits.
///
/// Keep the threshold much more than 1. The summarize operation of a client is
/// itself a sequenced message, so the drift becomes 1 after a checkpoint, and
/// not 0. A threshold of 1 would thus trigger again on its own announcement,
/// without an end.
pub fn policy() -> Policy {
  Policy(threshold: 500, jitter_milliseconds: 3000)
}

/// The number of sequenced messages past the checkpoint before the client
/// attempts a summary.
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
