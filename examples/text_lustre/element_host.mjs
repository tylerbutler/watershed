// A plain-JavaScript host for `<watershed-textarea>` — deliberately not a
// Lustre application.
//
// This is the custom-element wrapper's reason to exist: the nested MVU triple
// needs a parent that holds a child model and routes messages, which only a
// Lustre app can be. This page holds no model at all. It registers the
// element, connects with the plain `watershed_js` facade, assigns the live
// `SharedText` handle to the element's `channel` property, and from then on
// speaks DOM: `change`/`error`/`cursor` events out, a `peers` property in.
//
// Everything imported below is compiled Gleam, bundled by esbuild — including
// `doc_schema` from the Lustre app, so both hosts resolve the *same* `body`
// channel and a tab of each converges with shared cursors across the pair.

import { register } from "./build/dev/javascript/watershed_lustre/watershed_lustre/textarea_element.mjs";
import * as watershed from "./build/dev/javascript/watershed/watershed_js.mjs";
import * as presence_js from "./build/dev/javascript/watershed/watershed/presence_js.mjs";
import * as presence from "./build/dev/javascript/watershed/watershed/presence.mjs";
import * as decode from "./build/dev/javascript/gleam_stdlib/gleam/dynamic/decode.mjs";
import { Ok } from "./build/dev/javascript/prelude.mjs";
import { body } from "./build/dev/javascript/text_lustre/doc_schema.mjs";

// Dev config for `just server` (levee dev mode) — matches src/text_lustre.gleam.
const SOCKET_URL = "ws://localhost:4000/socket/websocket?vsn=2.0.0";
const TENANT = "dev-tenant";
const TENANT_SECRET = "levee-dev-secret-change-in-production";
const DOCUMENT_ID = "text";

// The same palette and hash as the Lustre app's `colour_for`, so a user keeps
// one colour however their peers happen to be hosted.
const PALETTE = ["#e5484d", "#0090ff", "#30a46c", "#f76b15", "#8e4ec6", "#e93d82"];
const colourFor = (userId) => {
  let total = 0;
  for (const point of userId) total += point.codePointAt(0);
  return PALETTE[total % PALETTE.length];
};

const status = document.getElementById("status");
const editor = document.getElementById("editor");
const errorLine = document.getElementById("error");
const lengthLine = document.getElementById("length");

// Register before touching the element: a property assigned before the tag is
// upgraded would shadow the class's `channel` setter and never be seen.
register();

// ── Outbound: the element speaks CustomEvents ────────────────────────────────

editor.addEventListener("change", (event) => {
  lengthLine.textContent = `${event.detail.length} graphemes`;
});

editor.addEventListener("error", (event) => {
  errorLine.textContent = event.detail.message ?? "";
});

// The element announces its own selection as a pair of content-bound anchors,
// already JSON — this host only decides what rides along and where it travels.
let handle = null;
let lastCursor = null;
editor.addEventListener("cursor", (event) => {
  lastCursor = event.detail;
  if (handle) presence_js.update(handle, { cursor: lastCursor });
});

// ── Connect, resolve the channel, hand it over ───────────────────────────────

const userId = `element-${Math.random().toString(36).slice(2, 6)}`;

const token = await watershed.dev_token(TENANT_SECRET, TENANT, DOCUMENT_ID, userId);
const config = new watershed.WatershedConfig(SOCKET_URL, TENANT, DOCUMENT_ID, token, userId);

const doc = watershed.connect(config, (ready) => {
  if (!ready.isOk()) {
    status.textContent = `connection failed · ${ready[0]}`;
    return;
  }
  status.textContent = `connected as ${userId}`;

  // Same bootstrap as the Lustre app: ensure the `body` slot holds a text
  // channel, creating one only if it is empty, so every tab converges on one
  // document. Needs the ready connection, hence inside `on_ready`.
  watershed.ensure_text(doc, watershed.root_typed(doc), body(), (ensured) => {
    if (!ensured.isOk()) {
      status.textContent = `body channel failed · ${ensured[0]}`;
      return;
    }

    // The whole integration: one property assignment.
    editor.channel = ensured[0];

    // Presence rides the same driver as the Lustre app (same wire shape:
    // `{cursor: …|null}`), so cursors cross host kinds. The decoder is a
    // passthrough — this host reads the metadata as plain data.
    const passthrough = decode.new_primitive_decoder("Meta", (value) => new Ok(value));
    const config = presence.config((meta) => meta, passthrough);
    handle = presence_js.start(doc, config, { cursor: lastCursor }, (event) => {
      // `State` replaces the roster, `Changed` carries the delta *and* the
      // resulting roster; both hand us a complete list, so one branch does.
      const entries = event.entries;
      if (entries === undefined) return;

      // Keyed by session, not user: two tabs of one person are two carets.
      const localSession = presence_js.local_session(handle)[0];
      editor.peers = [...entries]
        .filter((entry) => entry.session_id !== localSession && entry.meta?.cursor)
        .map((entry) => ({
          id: entry.session_id,
          label: entry.key,
          colour: colourFor(entry.key),
          cursor: entry.meta.cursor,
        }));
    });
  });
});
