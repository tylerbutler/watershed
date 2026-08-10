//// When a client should summarize the document on its own.
////
//// A document accumulates ops forever, and a joining client replays every one
//// of them unless a summary exists to start from. `summarize` has always been
//// able to write that checkpoint; this is the policy that decides *when*,
//// so an application does not have to.
////
//// **The shape: threshold, then jitter, then re-check.** Once more than
//// `threshold` messages have been sequenced past the last known checkpoint —
//// and the client is settled, see `runtime_core.wants_summary` — the runtime
//// waits a per-client delay derived from its client id and asks again. The
//// delay is what makes a room cheap: every client crosses the threshold on the
//// same message, but a summary is announced to the room, so the first one
//// sequenced advances everyone else's checkpoint and their re-check is a
//// no-op. A lost race costs one redundant upload, never a wrong document.
////
//// **The unit is sequenced messages, not edits.** A server sequences a batch
//// of submitted ops as one message, so a burst of edits moves the count by far
//// less than its length. That is the right unit — a joining client replays
//// messages — but it makes a threshold picked by imagining single edits much
//// too high.
////
//// **A summary needs traffic to happen.** The check runs when a message is
//// sequenced, so a document that falls quiet just past the threshold stays
//// there until the next edit. That edit summarizes; nothing is lost meanwhile.
////
//// **It is off unless asked for.** `watershed.auto_summarize` /
//// `watershed_js.auto_summarize` install a policy on a connected document;
//// without one nothing summarizes, which is the behaviour every existing
//// application already has.

/// A summarization policy: how far past the last checkpoint to let a document
/// drift, and how wide a window to spread the room's attempts over.
pub opaque type Policy {
  Policy(threshold: Int, jitter_ms: Int)
}

/// The default policy: summarize once 500 ops have been sequenced past the
/// last checkpoint, spreading attempts across a 3 second window.
///
/// The threshold is deliberately conservative. Too high and a joining client
/// still replays a long tail; too low and a busy document churns blobs, each
/// one a full snapshot of every channel. 500 sits under floodgate's 1000-message
/// in-band history window, so a joiner's catch-up stays in band — and it counts
/// sequenced messages, so it is a good deal more than 500 edits.
///
/// Keep it well above 1. A client's own summarize op is itself a sequenced
/// message, so the drift settles at 1 rather than 0 after a checkpoint; a
/// threshold of 1 would re-trigger on its own announcement forever.
pub fn policy() -> Policy {
  Policy(threshold: 500, jitter_ms: 3000)
}

/// Ops past the checkpoint before a summary is attempted.
pub fn with_threshold(policy: Policy, threshold: Int) -> Policy {
  Policy(..policy, threshold: threshold)
}

/// The window attempts are spread across. Zero fires immediately, which is
/// what a single-client test wants and what a populated room does not.
pub fn with_jitter_ms(policy: Policy, jitter_ms: Int) -> Policy {
  Policy(..policy, jitter_ms: jitter_ms)
}

pub fn policy_threshold(policy: Policy) -> Int {
  policy.threshold
}

pub fn policy_jitter_ms(policy: Policy) -> Int {
  policy.jitter_ms
}
