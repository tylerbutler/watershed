// The one browser capability `watershed/crdt_js` needs that Gleam cannot
// express: running an application callback without letting its exception
// escape into the document's own call stack.
//
// A subscriber is application code. If it throws, the document has already
// been written and every peer has already been sent the delta — the state is
// consistent — but the throw would still abandon the remaining subscribers
// and unwind whatever browser event was running. So it is caught here and
// handed back as a string, which the facade reports as a
// `SubscriberFailed` status. Nothing is silently swallowed.

export function guard(work, onError) {
  try {
    work();
  } catch (error) {
    onError(describe(error));
  }
  return undefined;
}

// Reference identity for two `crdt_core.Document` values, which Gleam has no
// operator for: `==` compiles to a structural comparison, and walking the
// whole document is the cost the digest cache exists to avoid.
//
// A document is immutable, so the same reference is the same state and the
// cached digest describes it. Two structurally equal documents that are
// different objects simply miss, which costs one recomputation and can never
// return a digest for a state this replica does not hold.

export function sameDocument(left, right) {
  return left === right;
}

function describe(error) {
  if (error instanceof Error) {
    return error.name + ": " + error.message;
  }
  return String(error);
}
