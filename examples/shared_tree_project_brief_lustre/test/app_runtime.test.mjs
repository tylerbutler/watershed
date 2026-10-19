import assert from "node:assert/strict";
import { test } from "node:test";
import * as app from "../build/dev/javascript/shared_tree_project_brief_lustre/shared_tree_project_brief_lustre.mjs";
import * as fixture from "../build/dev/javascript/shared_tree_project_brief_lustre/fixture.mjs";
import * as helpers from "../build/dev/javascript/shared_tree_project_brief_lustre/app_fixture.mjs";
import * as selection from "../build/dev/javascript/shared_tree_project_brief_lustre/shared_tree_project_brief_lustre/selection.mjs";
import * as presence from "../build/dev/javascript/watershed/watershed/presence.mjs";
import * as driver from "../build/dev/javascript/watershed/watershed/presence_js.mjs";
import * as watershed from "../build/dev/javascript/watershed/watershed.mjs";
import * as transport from "../build/dev/javascript/watershed/watershed/transport_js.mjs";
import * as effect from "../build/dev/javascript/lustre/lustre/effect.mjs";
import * as element from "../build/dev/javascript/lustre/lustre/element.mjs";
import { Some, None } from "../build/dev/javascript/gleam_stdlib/gleam/option.mjs";
import { Ok } from "../build/dev/javascript/prelude.mjs";

const title = new selection.Fixed(new selection.Title());
const review = new selection.Fixed(new selection.ReviewReviewer());
const none = new None();
const flush = async () => { for (let i = 0; i < 12; i++) await Promise.resolve(); };

function harness(model = helpers.model()) {
  const state = {
    model,
    send(message, run = true) {
      const [next, effects] = app.update(state.model, message);
      state.model = next;
      if (run) state.run(effects);
      return effects;
    },
    run(effects) {
      effect.perform(effects, (message) => {
        // Poll explicitly so these tests do not depend on wall-clock timing.
        state.send(message, !(message instanceof app.Poll));
      }, () => {}, () => {}, () => null, () => {}, () => {}, () => {});
    },
    html() { return element.to_string(app.view(state.model)); },
    peers() { return [...selection.peers(state.model.policy)]; },
    close() { state.send(new app.Close()); },
  };
  return state;
}

function fieldHtml(state, id = "title") {
  return state.html().match(new RegExp(`<input[^>]*id="field-${id}"[^>]*>`))?.[0];
}

function ripple(callbacks, session, meta, field = "title") {
  callbacks.on_event("signal", JSON.stringify({
    clientId: session,
    type: "presence",
    content: {
      kind: "presence", key: "same-user",
      meta: { name: meta.name, color: "blue", token: meta.token,
        selected: meta.selected instanceof Some
          ? { kind: "fixed", field } : null },
    },
  }));
}

function operations(submissions) {
  return [...transport.get_cell(submissions)]
    .reverse()
    .filter(([event]) => event === "submitOp")
    .flatMap(([, payload]) => {
      const { clientId, messageBatches } = JSON.parse(payload);
      return messageBatches.flat().map((op) => ({ ...op, clientId }));
    });
}

function acknowledge(callbacks, submissions) {
  const ops = operations(submissions).map((op, index) => ({
    ...op, sequenceNumber: index + 1, minimumSequenceNumber: 0, timestamp: 0,
  }));
  callbacks.on_event("op", JSON.stringify(ops));
  return ops.length;
}

test("app starts presence before handshake and keeps it after ready and reconnect", async (t) => {
  t.mock.timers.enable({ apis: ["Date", "setTimeout"] });
  const [document, callbacks, submissions] = fixture.pending(helpers.initial());
  const state = harness();
  try {
    state.send(new app.GotDocument(document));
    await flush();
    fixture.handshake(callbacks, "local-1");
    await flush();
    state.send(new app.Connected(new Ok(undefined)));
    await flush();
    state.send(new app.Poll(), false);
    const handle = state.model.presence[0];
    assert.ok(handle, "GotDocument must register a driver before the handshake");
    assert.deepEqual(driver.local_session(handle), new Some("local-1"));
    assert.deepEqual(driver.mode(handle), new Some(new presence.Ripple()));
    state.send(new app.Focus(new Some(title)));
    await flush();
    assert.deepEqual(driver.local_session(handle), new Some("local-1"));

    const meta = new selection.Metadata("Peer", new selection.Blue(), 1, new Some(title));
    ripple(callbacks, "remote", meta);
    await flush();
    assert.equal(state.peers().length, 1);
    assert.match(state.html(), /data-session-id="remote"/);
    watershed.go_offline(document);
    state.send(new app.Poll(), false);
    assert.equal(state.peers().length, 0);
    ripple(callbacks, "offline-peer", meta);
    watershed.go_online(document);
    fixture.handshake(callbacks, "local-2");
    await flush();
    state.send(new app.Poll(), false);
    assert.equal(state.model.presence[0], handle, "Reconnect must retain the initialized driver");
    assert.deepEqual(driver.local_session(handle), new Some("local-2"));
    assert.equal(state.peers().length, 0, "Cached remote roster must stay hidden");
    // The metadata is unchanged, so the driver emits no Changed callback.
    ripple(callbacks, "remote", meta);
    await flush();
    assert.equal(state.peers().length, 1, "A freshly observed unchanged heartbeat must restore awareness");
    assert.match(state.html(), /data-session-id="remote"/);
    assert.equal(state.model.change_count, 0, "Awareness must not write the tree");
    assert.equal(operations(submissions).length, 0);
    for (let i = 0; i < 4; i++) {
      t.mock.timers.tick(2000);
      await flush();
    }
    assert.equal(state.peers().length, 0, "The existing driver's expiry must remove freshly observed peers");
  } finally { state.close(); watershed.close(document); }
});

test("disconnect before the next diagnostics tick cannot submit a composition end", async () => {
  const { document } = fixture.new$(helpers.initial());
  const state = harness(helpers.opened(document));
  try {
    const write = helpers.title_write(state.model);
    state.send(new app.Input(title, write, new app.CompositionStarted()));
    watershed.go_offline(document);
    state.send(new app.Input(title, write, new app.CompositionEnded("offline", 7, 7)), false);
    assert.equal(state.model.pending, 0, "The durable gate must consult current runtime readiness");
    assert.match(fieldHtml(state), /\bvalue=/);
  } finally { state.close(); watershed.close(document); }
});

test("rendered input omits value during composition and offline cleanup permits later edits", async () => {
  const [document, callbacks, submissions] = fixture.pending(helpers.initial());
  const state = harness();
  try {
    state.send(new app.GotDocument(document));
    await flush();
    fixture.handshake(callbacks, "local-1");
    state.send(new app.Connected(new Ok(undefined)));
    await flush();
    state.send(new app.Poll(), false);
    const write = helpers.title_write(state.model);
    state.send(new app.Input(title, write, new app.CompositionStarted()));
    assert.doesNotMatch(fieldHtml(state), /\bvalue=/);
    watershed.go_offline(document);
    state.send(new app.Poll(), false);
    assert.match(fieldHtml(state), /\bdisabled/);
    assert.match(fieldHtml(state), /\bvalue=/, "Disabling cancels composition even if no end event arrives");
    state.send(new app.Input(title, write, new app.CompositionEnded("offline", 7, 7)));
    state.send(new app.Input(title, write, new app.Changed("offline", 7, 7)));
    await flush();
    assert.equal(state.model.pending, 0, "Offline composition must not schedule durable writes");
    assert.equal(operations(submissions).length, 0);
    assert.doesNotMatch(fieldHtml(state), /value="offline"/);
    watershed.go_online(document);
    fixture.handshake(callbacks, "local-2");
    await flush();
    state.send(new app.Poll(), false);
    state.send(helpers.capture(state.model));
    assert.match(fieldHtml(state), /value="Release brief"/, "Offline DOM events must not change the tree");
    state.send(new app.Input(title, write, new app.Changed("later", 5, 5)));
    await flush();
    state.send(helpers.capture(state.model));
    assert.match(fieldHtml(state), /value="later"/);
    state.send(new app.Input(title, write, new app.CompositionStarted()));
    state.close();
    assert.match(fieldHtml(state), /\bvalue=/, "Close must also cancel local composition");
  } finally { state.close(); watershed.close(document); }
});

test("review remove/recreate between app captures invalidates old local and remote selection tokens", async () => {
  const [document, callbacks, submissions] = fixture.pending(helpers.with_review());
  const state = harness();
  try {
    state.send(new app.GotDocument(document));
    await flush();
    fixture.handshake(callbacks, "local-1");
    state.send(new app.Connected(new Ok(undefined)));
    await flush();
    state.send(new app.Poll(), false);
    state.send(new app.Focus(new Some(review)));
    const metadata = new selection.Metadata("Peer", new selection.Blue(), 8, new Some(review));
    ripple(callbacks, "remote", metadata, "review.reviewer");
    await flush();
    assert.match(state.html(), /data-session-id="remote"/);
    helpers.replace_review(state.model);
    state.send(helpers.capture(state.model));
    assert.deepEqual(state.model.metadata.selected, none);
    assert.equal(state.model.metadata.token, 2);
    assert.deepEqual(state.peers()[0].meta.selected, none);
    await flush();
    const checkpoint = acknowledge(callbacks, submissions);
    await flush();
    assert.equal(watershed.is_synced(document), true);
    watershed.go_offline(document);
    state.send(new app.Poll(), false);
    assert.equal(state.peers().length, 0);
    watershed.go_online(document);
    fixture.handshake_at(callbacks, "local-2", checkpoint);
    await flush();
    state.send(new app.Poll(), false);
    ripple(callbacks, "remote", metadata, "review.reviewer");
    await flush();
    assert.deepEqual(state.peers()[0].meta.selected, none, "Old heartbeat cannot target the replacement");
    const fresh = new selection.Metadata("Peer", new selection.Blue(), 9, new Some(review));
    ripple(callbacks, "remote", fresh, "review.reviewer");
    await flush();
    assert.deepEqual(state.peers()[0].meta.selected, new Some(review));
    assert.equal(state.model.rendered[0].value.review[0].reviewer, "New");
  } finally { state.close(); watershed.close(document); }
});
