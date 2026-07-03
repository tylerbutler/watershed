// Live convergence demo. The two "clients" here each own a real
// `watershed/map_kernel` state — the same pure Gleam module the BEAM runtime
// uses, compiled with `gleam build --target javascript` — and talk through a
// tiny in-page sequencer that stamps CSNs and broadcasts in order, the same
// protocol shape as a live levee server.
import * as kernel from "../../../build/dev/javascript/watershed/watershed/map_kernel.mjs";
import * as json from "../../../build/dev/javascript/gleam_json/gleam/json.mjs";
import { toList } from "../../../build/dev/javascript/watershed/gleam.mjs";

const GAUGES = ["mill-race", "kettle-run", "low-ford"];
const INITIAL = [
  ["mill-race", 24],
  ["kettle-run", 61],
  ["low-ford", 42],
];

const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

function jsonInt(n) {
  return json.int(n);
}

function readInt(optionValue) {
  // `get` returns Option(Json); Some stores its payload at [0]. Json values
  // stringify via the gleam encoder, so ints round-trip through Number().
  if (optionValue && optionValue[0] !== undefined) {
    return Number(json.to_string(optionValue[0]));
  }
  return null;
}

function pendingKeys(state) {
  const keys = new Set();
  for (const entry of state.pending.toArray()) {
    if (entry instanceof kernel.PendingLifetime) keys.add(entry.key);
    else if (entry instanceof kernel.PendingDelete) keys.add(entry.key);
    else for (const k of GAUGES) keys.add(k); // PendingClear masks everything
  }
  return keys;
}

function describeOp(op) {
  if (op instanceof kernel.Set) {
    return `set ${op.key} = ${json.to_string(op.value)}`;
  }
  if (op instanceof kernel.Delete) return `delete ${op.key}`;
  return "clear";
}

export function initDemo() {
  const rig = document.querySelector("[data-demo-rig]");
  if (!rig) return;

  const flowLayer = rig.querySelector("[data-flow-layer]");
  const seqNode = rig.querySelector("[data-seq-node]");
  const seqCounter = rig.querySelector("[data-seq-counter]");
  const opLog = rig.querySelector("[data-op-log]");
  const statusEl = document.querySelector("[data-status]");
  const latencyInput = document.querySelector("[data-latency]");
  const latencyOut = document.querySelector("[data-latency-out]");
  const raceBtn = document.querySelector("[data-race]");

  const initial = toList(INITIAL.map(([k, v]) => [k, jsonInt(v)]));

  const clients = {};
  for (const id of ["a", "b"]) {
    clients[id] = {
      id,
      state: kernel.from_sequenced(initial),
      el: rig.querySelector(`[data-client="${id}"]`),
      lastArrival: 0, // enforces FIFO delivery from the sequencer
    };
  }

  let latency = Number(latencyInput.value);
  let csn = 0;
  let inFlight = 0;
  let seqLastArrival = 0; // FIFO into the sequencer too

  // ── rendering ─────────────────────────────────────────────────────────────

  function render(client) {
    const pending = pendingKeys(client.state);
    for (const key of GAUGES) {
      const row = client.el.querySelector(`tr[data-key="${key}"]`);
      const value = readInt(kernel.get(client.state, key));
      row.querySelector("[data-value]").textContent =
        value === null ? "—" : String(value);
      row.classList.toggle("pending", pending.has(key));
    }
    const count = client.state.pending.toArray().length;
    const badge = client.el.querySelector("[data-pending-count]");
    badge.textContent = `${count} pending`;
    if (count === 0) badge.setAttribute("data-zero", "");
    else badge.removeAttribute("data-zero");
  }

  function renderStatus() {
    const pendingTotal =
      clients.a.state.pending.toArray().length +
      clients.b.state.pending.toArray().length;
    if (inFlight === 0 && pendingTotal === 0) {
      const same =
        JSON.stringify(snapshot(clients.a.state)) ===
        JSON.stringify(snapshot(clients.b.state));
      statusEl.innerHTML = same
        ? `<span class="stamp converged">Converged</span> replicas identical · nothing pending`
        : `<span class="stamp revising">Diverged</span> this should be impossible — please file a bug`;
    } else {
      statusEl.innerHTML = `<span class="stamp revising">Revising</span> ${inFlight} op${inFlight === 1 ? "" : "s"} in flight · ${pendingTotal} pending`;
    }
  }

  function snapshot(state) {
    return kernel
      .sequenced_entries(state)
      .toArray()
      .map(([k, v]) => [k, json.to_string(v)]);
  }

  function logOp(stampedCsn, origin, op) {
    const li = document.createElement("li");
    li.textContent = `#${String(stampedCsn).padStart(2, "0")} ${describeOp(op)} · from ${origin.toUpperCase()}`;
    opLog.prepend(li);
    while (opLog.children.length > 14) opLog.lastChild.remove();
    seqCounter.textContent = `CSN ${stampedCsn}`;
    seqCounter.classList.remove("stamped");
    void seqCounter.offsetWidth;
    seqCounter.classList.add("stamped");
  }

  // ── op flow animation ─────────────────────────────────────────────────────

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

  // ── protocol: client → sequencer → broadcast ──────────────────────────────

  function submit(originId, op) {
    const origin = clients[originId];
    inFlight += 1;
    renderStatus();
    animateDot(origin.el, seqNode, latency, false);

    // FIFO into the sequencer: an op may not overtake an earlier one even if
    // the latency slider moved while it was in flight.
    const now = performance.now();
    const arrival = Math.max(now + latency, seqLastArrival + 25);
    seqLastArrival = arrival;

    setTimeout(() => {
      csn += 1;
      const stamped = csn;
      logOp(stamped, originId, op);

      for (const target of Object.values(clients)) {
        animateDot(seqNode, target.el, latency, true);
        const tNow = performance.now();
        const tArrival = Math.max(tNow + latency, target.lastArrival + 25);
        target.lastArrival = tArrival;
        inFlight += 1;
        setTimeout(() => {
          if (target.id === originId) {
            const result = kernel.ack_local(target.state, op);
            if (result.isOk()) target.state = result[0];
            else console.error("unexpected ack", result[0]);
          } else {
            const [next] = kernel.apply_remote(target.state, op);
            target.state = next;
          }
          inFlight -= 1;
          render(target);
          renderStatus();
        }, tArrival - tNow);
      }

      inFlight -= 1;
      renderStatus();
    }, arrival - now);
  }

  function localSet(clientId, key, value) {
    const client = clients[clientId];
    const [next, _events, op] = kernel.set(client.state, key, jsonInt(value));
    client.state = next;
    render(client);
    submit(clientId, op);
  }

  // ── wiring ────────────────────────────────────────────────────────────────

  for (const client of Object.values(clients)) {
    client.el.addEventListener("click", (event) => {
      const button = event.target.closest("button[data-step]");
      if (!button) return;
      const key = button.closest("tr").dataset.key;
      const current = readInt(kernel.get(client.state, key)) ?? 0;
      localSet(client.id, key, current + Number(button.dataset.step));
    });
  }

  latencyInput.addEventListener("input", () => {
    latency = Number(latencyInput.value);
    latencyOut.textContent = `${latency} ms`;
  });

  raceBtn.addEventListener("click", () => {
    // Both clients write the same key inside one latency window. The op the
    // server sequences last wins on every replica — that's LWW, and both
    // replicas agree because they apply ops in the same order.
    const key = GAUGES[Math.floor(Math.random() * GAUGES.length)];
    const base = readInt(kernel.get(clients.a.state, key)) ?? 0;
    localSet("a", key, base + 10);
    localSet("b", key, base - 10);
  });

  render(clients.a);
  render(clients.b);
  renderStatus();
}
