/// <reference types="./summary_policy.d.mts" />
import { CustomType as $CustomType } from "../gleam.mjs";

class Policy extends $CustomType {
  constructor(threshold, jitter_milliseconds) {
    super();
    this.threshold = threshold;
    this.jitter_milliseconds = jitter_milliseconds;
  }
}

/**
 * The default policy. It attempts a summary after 500 messages sequence past
 * the last checkpoint. It spreads the attempts across a 3 second window.
 *
 * The threshold is conservative on purpose. A threshold that is too high makes
 * a client that joins replay a long tail. A threshold that is too low makes a
 * busy document write many blobs, and each blob is a full snapshot of every
 * channel. 500 is less than the 1000-message in-band history window of
 * floodgate. This leaves room for messages during the delay and upload, but
 * does not guarantee an in-band catch-up. Failures and clients that are not
 * settled can also extend the history. A message can contain multiple edits.
 *
 * Keep the threshold much more than 1. The summarize operation of a client is
 * itself a sequenced message, so the drift becomes 1 after a checkpoint, and
 * not 0. A threshold of 1 would thus trigger again on its own announcement,
 * without an end.
 */
export function policy() {
  return new Policy(500, 3000);
}

/**
 * The number of sequenced messages past the checkpoint before the client
 * attempts a summary.
 */
export function with_threshold(policy, threshold) {
  return new Policy(threshold, policy.jitter_milliseconds);
}

/**
 * The window that the attempts spread across. A value of zero starts the
 * attempt immediately. A test with one client needs that value. A room with
 * many clients does not.
 */
export function with_jitter_milliseconds(policy, jitter_milliseconds) {
  return new Policy(policy.threshold, jitter_milliseconds);
}

export function policy_threshold(policy) {
  return policy.threshold;
}

export function policy_jitter_milliseconds(policy) {
  return policy.jitter_milliseconds;
}
