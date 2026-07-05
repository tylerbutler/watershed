// Live JSON-OT convergence demo. Each of the three "clients" owns real
// watershed state — a `json_ot_kernel` client-transform state machine compiled
// with `gleam build --target javascript` — over one shared JSON document. They
// talk through a tiny in-page sequencer that stamps sequence numbers (SNs) and
// broadcasts in order, the same protocol shape a Fluid-compatible service uses.
//
// Unlike the CRDT structures on the homepage, this kernel *transforms*: it keeps
// at most one op in flight (the Wave/ShareDB client model), rebases the in-flight
// op past every concurrent remote op, and transforms incoming ops into head
// context. Concurrent list inserts at the same index are the star — OT shifts
// indices so every replica converges to the identical array.
import * as kernel from "../../../build/dev/javascript/watershed/watershed/json_ot_kernel.mjs";
import * as jsonOt from "../../../build/dev/javascript/watershed/watershed/json_ot.mjs";
import { None, Some } from "../../../build/dev/javascript/gleam_stdlib/gleam/option.mjs";
import { toList } from "../../../build/dev/javascript/watershed/gleam.mjs";

// ── value / component builders ─────────────────────────────────────────────
const S = (s) => new jsonOt.VString(s);
const N = (n) => new jsonOt.VNumber(new jsonOt.NInt(n));
const K = (k) => new jsonOt.Key(k);
const IDX = (i) => new jsonOt.Index(i);
const path = (...keys) => toList(keys);
const op = (...components) => toList(components);

function vArray(values) {
  return new jsonOt.VArray(toList(values.map(S)));
}

// VObject members are held sorted by key so `==` is a canonical convergence
// oracle; build the baseline the same way the kernel keeps it.
function vObject(pairs) {
  const sorted = [...pairs].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  return new jsonOt.VObject(toList(sorted.map(([k, v]) => [k, v])));
}

const CREW_BASE = ["Ada", "Ben"];
const SITE_BASE = "Mill Race";
const STAGE_BASE = 24;
// Names each client cycles through when it adds a surveyor to the crew list.
const NEW_NAMES = ["Cy", "Dot", "Eli", "Fen", "Gus", "Hana", "Ime", "Jo"];
const SITE_NAMES = ["Mill Race", "Kettle Run", "Low Ford", "Spillway Gate"];

function baselineDoc() {
  return vObject([
    ["crew", vArray(CREW_BASE)],
    ["site", S(SITE_BASE)],
    ["stage", N(STAGE_BASE)],
  ]);
}

// ── JsonValue → plain JS (for reading + rendering) ─────────────────────────
function toPlain(v) {
  if (v instanceof jsonOt.VNull) return null;
  if (v instanceof jsonOt.VBool) return v[0];
  if (v instanceof jsonOt.VNumber) return v[0][0]; // NInt/NFloat both hold [0]
  if (v instanceof jsonOt.VString) return v[0];
  if (v instanceof jsonOt.VArray) return v[0].toArray().map(toPlain);
  if (v instanceof jsonOt.VObject) {
    const out = {};
    for (const [k, val] of v[0].toArray()) out[k] = toPlain(val);
    return out;
  }
  return null;
}

const CLIENT_IDS = ["a", "b", "c"];
const CLIENT_NUM = { a: 0, b: 1, c: 2 };
const CLIENT_LABEL = { a: "Client A", b: "Client B", c: "Client C" };

export function initJsonOtDemo() {
  const rig = document.querySelector("[data-jot-rig]");
  if (!rig) return;

  const flowLayer = rig.querySelector("[data-flow-layer]");
  const seqNode = rig.querySelector("[data-seq-node]");
  const seqCounter = rig.querySelector("[data-seq-counter]");
  const opLog = rig.querySelector("[data-op-log]");
  const statusEl = document.querySelector("[data-jot-status]");
  const latencyInput = document.querySelector("[data-jot-latency]");
  const latencyOut = document.querySelector("[data-jot-latency-out]");
  const raceBtn = document.querySelector("[data-jot-race]");
  const resetBtn = document.querySelector("[data-jot-reset]");
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  // Controls ship disabled so nothing is interactive before the kernel loads.
  const section = document.querySelector("#jot-demo");
  for (const el of section.querySelectorAll("button, input")) el.disabled = false;

  const clients = {};
  for (const id of CLIENT_IDS) {
    clients[id] = {
      id,
      num: CLIENT_NUM[id],
      state: kernel.from_value(CLIENT_NUM[id], baselineDoc()),
      el: rig.querySelector(`[data-client="${id}"]`),
      lastAppliedSn: 0, // last global SN this replica has applied
      lastArrival: 0, // enforces FIFO, in-order delivery per replica
    };
  }

  let latency = Number(latencyInput.value);
  let sn = 0; // global sequence number stamped by the sequencer
  let inFlight = 0; // ops travelling on the wire, for the status line
  let seqLastArrival = 0; // FIFO into the sequencer
  let epoch = 0; // bumped on reset so stale timers bail out
  const nameCursor = { a: 0, b: 0, c: 0 };
  const siteCursor = { a: 0, b: 0, c: 0 };

  latencyOut.textContent = `${latency} ms`;

  // ── flow dots ─────────────────────────────────────────────────────────────
  function anchor(el) {
    const layerBox = flowLayer.getBoundingClientRect();
    const box = el.getBoundingClientRect();
    return [
      box.left + box.width / 2 - layerBox.left,
      box.top + box.height / 2 - layerBox.top,
    ];
  }

  function animateDot(fromEl, toEl, duration, sequenced) {
    if (reducedMotion.matches) return;
    const dot = document.createElement("span");
    dot.className = sequenced ? "flow-dot sequenced" : "flow-dot";
    flowLayer.append(dot);
    const [x0, y0] = anchor(fromEl);
    const [x1, y1] = anchor(toEl);
    const anim = dot.animate(
      [
        { transform: `translate(${x0 - 5}px, ${y0 - 5}px)`, opacity: 0.3 },
        { transform: `translate(${x1 - 5}px, ${y1 - 5}px)`, opacity: 1 },
      ],
      { duration: Math.max(180, duration), easing: "ease-in-out" },
    );
    anim.onfinish = () => dot.remove();
  }

  // ── rendering ──────────────────────────────────────────────────────────────
  function optimistic(client) {
    const view = kernel.view(client.state);
    return view.isOk() ? toPlain(view[0]) : null;
  }

  function sequenced(client) {
    return toPlain(kernel.summary(client.state));
  }

  function pendingCount(client) {
    let n = 0;
    const inflight = client.state.inflight;
    const buffer = client.state.buffer;
    if (inflight instanceof Some) n += inflight[0].toArray().length;
    if (buffer instanceof Some) n += buffer[0].toArray().length;
    return n;
  }

  // Consume a multiset of sequenced crew names so a chip is drawn "sequenced"
  // (ink) if the server has it and "pending" (magenta) if it is a local-only add.
  function crewChips(optCrew, seqCrew) {
    const remaining = [...seqCrew];
    return optCrew.map((name) => {
      const at = remaining.indexOf(name);
      if (at >= 0) {
        remaining.splice(at, 1);
        return { name, pending: false };
      }
      return { name, pending: true };
    });
  }

  function render(client) {
    const opt = optimistic(client);
    const seq = sequenced(client);
    if (!opt) return;
    const el = client.el;

    // site
    const siteEl = el.querySelector("[data-field='site'] [data-value]");
    siteEl.textContent = opt.site;
    siteEl.classList.toggle("pending", opt.site !== seq.site);

    // stage
    const stageEl = el.querySelector("[data-field='stage'] [data-value]");
    stageEl.textContent = opt.stage;
    stageEl.classList.toggle("pending", opt.stage !== seq.stage);

    // crew
    const crewEl = el.querySelector("[data-crew]");
    crewEl.replaceChildren();
    const chips = crewChips(opt.crew, seq.crew);
    chips.forEach((chip, index) => {
      const li = document.createElement("li");
      li.className = chip.pending ? "chip pending" : "chip";

      const openQuote = document.createElement("span");
      openQuote.className = "jp";
      openQuote.textContent = '"';
      li.append(openQuote);

      const label = document.createElement("span");
      label.className = "chip-name";
      label.textContent = chip.name;
      li.append(label);

      const closeQuote = document.createElement("span");
      closeQuote.className = "jp";
      closeQuote.textContent = index < chips.length - 1 ? '",' : '"';
      li.append(closeQuote);

      const actions = document.createElement("span");
      actions.className = "chip-actions";
      if (index > 0) {
        const up = document.createElement("button");
        up.type = "button";
        up.textContent = "↑";
        up.setAttribute("aria-label", `Move ${chip.name} up on ${CLIENT_LABEL[client.id]}`);
        up.addEventListener("click", () => localCrewMove(client.id, index));
        actions.append(up);
      }
      const del = document.createElement("button");
      del.type = "button";
      del.textContent = "×";
      del.setAttribute("aria-label", `Remove ${chip.name} on ${CLIENT_LABEL[client.id]}`);
      del.addEventListener("click", () => localCrewDelete(client.id, index));
      actions.append(del);

      li.append(actions);
      crewEl.append(li);
    });

    const count = pendingCount(client);
    const badge = el.querySelector("[data-pending-count]");
    badge.textContent = `${count} pending`;
    badge.classList.toggle("is-pending", count > 0);
  }

  // ── status ─────────────────────────────────────────────────────────────────
  function converged() {
    const sigs = CLIENT_IDS.map((id) => JSON.stringify(sequenced(clients[id])));
    const pending = CLIENT_IDS.some((id) => pendingCount(clients[id]) > 0);
    const identical = sigs.every((s) => s === sigs[0]);
    return identical && !pending && inFlight === 0;
  }

  function renderStatus() {
    const ok = converged();
    const stamp = ok
      ? '<span class="stamp converged">Converged</span> replicas identical · nothing pending'
      : '<span class="stamp revising">Revising</span> transforming ops in flight';
    statusEl.innerHTML = stamp;
  }

  function stampSeqCounter() {
    seqCounter.textContent = `SN\u00a0${sn}`;
    seqCounter.classList.remove("stamped");
    void seqCounter.offsetWidth;
    seqCounter.classList.add("stamped");
  }

  function logOp(seq, authorId, spot) {
    const li = document.createElement("li");

    const meta = document.createElement("span");
    meta.className = "op-meta";
    meta.textContent = `SN ${seq} · ${CLIENT_LABEL[authorId].replace("Client ", "")}`;

    const pathEl = document.createElement("span");
    pathEl.className = "op-path";
    pathEl.textContent = spot.path;

    const kindEl = document.createElement("span");
    kindEl.className = "op-kind";
    kindEl.textContent = spot.value ? `${spot.kind} ${spot.value}` : spot.kind;

    li.append(meta, pathEl, kindEl);
    opLog.prepend(li);
    while (opLog.children.length > 24) opLog.lastChild.remove();
  }

  // ── protocol: client → sequencer → broadcast ───────────────────────────────
  function sendToSequencer(client, wire, spot, authorId) {
    inFlight += 1;
    renderStatus();
    animateDot(client.el, seqNode, latency, false);
    const now = performance.now();
    const arrival = Math.max(now + latency, seqLastArrival + 25);
    seqLastArrival = arrival;
    const myEpoch = epoch;
    setTimeout(() => {
      if (myEpoch !== epoch) return;
      sn += 1;
      const seq = sn;
      stampSeqCounter();
      logOp(seq, authorId, spot);
      for (const target of Object.values(clients)) {
        animateDot(seqNode, target.el, latency, true);
        const tNow = performance.now();
        const tArrival = Math.max(tNow + latency, target.lastArrival + 25);
        target.lastArrival = tArrival;
        inFlight += 1;
        setTimeout(() => {
          if (myEpoch !== epoch) {
            inFlight -= 1;
            renderStatus();
            return;
          }
          deliver(target, client.num, wire, seq, spot, authorId);
          inFlight -= 1;
          render(target);
          pulseNode(target, spot.node, true);
          renderStatus();
        }, tArrival - tNow);
      }
      inFlight -= 1;
      renderStatus();
    }, arrival - now);
  }

  const MSN = 0; // demo keeps the whole concurrency window (never GCs the log)

  function deliver(target, authorNum, wire, seq, spot, authorId) {
    if (target.num === authorNum) {
      // Our own op comes back sequenced: commit it, then release any buffered op.
      const acked = kernel.ack_local(target.state, wire, seq, MSN);
      if (!acked.isOk()) return;
      target.state = acked[0][0];
      const [drained, out] = kernel.take_outbound(target.state);
      target.state = drained;
      target.lastAppliedSn = seq;
      if (out instanceof Some) {
        sendToSequencer(target, out[0], spot, authorId);
      }
    } else {
      const applied = kernel.apply_remote(target.state, wire, seq, authorNum, MSN);
      if (!applied.isOk()) return;
      target.state = applied[0][0];
      target.lastAppliedSn = seq;
    }
  }

  function pulseNode(client, node, sequenced) {
    const row = client.el.querySelector(`[data-node="${node}"]`);
    if (!row) return;
    const cls = sequenced ? "touch-seq" : "touch-pending";
    row.classList.remove("touch-seq", "touch-pending");
    void row.offsetWidth;
    row.classList.add(cls);
    setTimeout(() => row.classList.remove(cls), 640);
  }

  // Author a local edit: optimistic apply now, wire op to the sequencer if the
  // kernel released one (nothing already in flight for this client). `spot`
  // names the JSON node the op touches, so the UI can pulse it and the op log
  // can print a real path.
  function localEdit(clientId, components, spot) {
    const client = clients[clientId];
    const result = kernel.submit(client.state, components, client.lastAppliedSn);
    if (!result.isOk()) return;
    const [state, wireOpt] = result[0];
    client.state = state;
    render(client);
    pulseNode(client, spot.node, false);
    renderStatus();
    if (wireOpt instanceof Some) {
      sendToSequencer(client, wireOpt[0], spot, clientId);
    }
  }

  // ── local operations ─────────────────────────────────────────────────────
  function localStage(clientId, delta) {
    const sign = delta > 0 ? "+" : "";
    localEdit(
      clientId,
      op(jsonOt.number_add(path(K("stage")), new jsonOt.NInt(delta))),
      { node: "stage", path: ".stage", kind: "add", value: `${sign}${delta}` },
    );
  }

  function localSite(clientId) {
    const client = clients[clientId];
    const current = optimistic(client).site;
    const next = SITE_NAMES[siteCursor[clientId] % SITE_NAMES.length];
    siteCursor[clientId] += 1;
    if (next === current) return localSite(clientId);
    localEdit(
      clientId,
      op(jsonOt.obj_replace(path(K("site")), S(current), S(next))),
      { node: "site", path: ".site", kind: "set", value: `"${next}"` },
    );
  }

  function localCrewAdd(clientId) {
    const name = NEW_NAMES[nameCursor[clientId] % NEW_NAMES.length];
    nameCursor[clientId] += 1;
    localEdit(
      clientId,
      op(jsonOt.list_insert(path(K("crew"), IDX(0)), S(name))),
      { node: "crew", path: ".crew[0]", kind: "insert", value: `"${name}"` },
    );
  }

  function localCrewDelete(clientId, index) {
    const client = clients[clientId];
    const crew = optimistic(client).crew;
    const name = crew[index];
    localEdit(
      clientId,
      op(jsonOt.list_delete(path(K("crew"), IDX(index)), S(name))),
      { node: "crew", path: `.crew[${index}]`, kind: "delete", value: `"${name}"` },
    );
  }

  function localCrewMove(clientId, index) {
    localEdit(
      clientId,
      op(jsonOt.list_move(path(K("crew"), IDX(index)), index - 1)),
      { node: "crew", path: `.crew[${index}]`, kind: "move", value: `→ ${index - 1}` },
    );
  }

  // ── static button wiring (stage / site / add) ──────────────────────────────
  for (const id of CLIENT_IDS) {
    const el = clients[id].el;
    el.querySelector("[data-stage-inc]").addEventListener("click", () => localStage(id, 1));
    el.querySelector("[data-stage-dec]").addEventListener("click", () => localStage(id, -1));
    el.querySelector("[data-site-cycle]").addEventListener("click", () => localSite(id));
    el.querySelector("[data-crew-add]").addEventListener("click", () => localCrewAdd(id));
  }

  latencyInput.addEventListener("input", () => {
    latency = Number(latencyInput.value);
    latencyOut.textContent = `${latency} ms`;
  });

  // Two clients insert a surveyor at the front of the crew list at the same
  // instant. The sequencer picks an order; OT transforms the loser's index past
  // the winner so both names survive and every replica lands the same array.
  raceBtn.addEventListener("click", () => {
    const nameA = NEW_NAMES[nameCursor.a % NEW_NAMES.length];
    nameCursor.a += 1;
    const nameB = NEW_NAMES[nameCursor.b % NEW_NAMES.length];
    nameCursor.b += 1;
    localEdit(
      "a",
      op(jsonOt.list_insert(path(K("crew"), IDX(0)), S(nameA))),
      { node: "crew", path: ".crew[0]", kind: "insert", value: `"${nameA}"` },
    );
    localEdit(
      "b",
      op(jsonOt.list_insert(path(K("crew"), IDX(0)), S(nameB))),
      { node: "crew", path: ".crew[0]", kind: "insert", value: `"${nameB}"` },
    );
  });

  resetBtn.addEventListener("click", () => {
    epoch += 1; // strand any timers still in flight
    sn = 0;
    inFlight = 0;
    seqLastArrival = 0;
    for (const id of CLIENT_IDS) {
      const client = clients[id];
      client.state = kernel.from_value(client.num, baselineDoc());
      client.lastAppliedSn = 0;
      client.lastArrival = 0;
      nameCursor[id] = 0;
      siteCursor[id] = 0;
      render(client);
    }
    seqCounter.textContent = "SN\u00a00";
    opLog.replaceChildren();
    renderStatus();
  });

  // ── first paint ────────────────────────────────────────────────────────────
  for (const id of CLIENT_IDS) render(clients[id]);
  renderStatus();
}
