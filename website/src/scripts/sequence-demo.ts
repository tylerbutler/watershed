// Live SharedSequence convergence demo: three real watershed documents share
// one ordered portage route, driven through the in-memory sluice (see
// ./demo/sluice-rig.ts for the shared orchestration). Client A creates the
// sequence via the JS facade and attaches its handle under the root map; the
// others resolve it. From there, edits are ordinary facade calls the sluice
// sequences — the runtime owns optimistic apply, pending, and resubmit — so
// the demo just issues inserts/moves/renames/deletes and reads values back.
import * as watershed from "../../../build/dev/javascript/watershed/watershed_js.mjs";
import * as runtime from "../../../build/dev/javascript/watershed/watershed/runtime_js.mjs";
import * as sluice from "../../../build/dev/javascript/watershed/watershed/sluice_js.mjs";
import * as json from "../../../build/dev/javascript/gleam_json/gleam/json.mjs";
import { createSluiceRig, some, type RigClient } from "./demo/sluice-rig.ts";
import { createRigNotes, type RigNotes } from "./demo/rig-notes.ts";

const CLIENT_IDS = ["a", "b", "c"];
const CLIENT_LABEL: Record<string, string> = {
  a: "Client A",
  b: "Client B",
  c: "Client C",
};
// The route the demo starts with, upstream → downstream.
const INITIAL_ROUTE = [
  "put-in",
  "mill-race weir",
  "kettle-run rapids",
  "low-ford portage",
  "take-out",
];
// Pool for inserted/renamed waypoints. Names are kept unique on the route so
// stations can be keyed (and slide-animated) by name.
const SPARE_NAMES = [
  "beaver dam",
  "gravel bar",
  "oxbow",
  "sweeper",
  "boulder garden",
  "eddy pool",
  "cache point",
  "lining chute",
  "high camp",
];
const SEQ_ADDRESS = "route"; // root-map key holding the sequence handle

// ── geometry (pixel units, shared by stations and the SVG river) ────────────
const ROW_H = 56;
const PAD_Y = 20;
const MEANDER = [0, 26, 42, 26, 0, -22, -36, -22];
const SVG_NS = "http://www.w3.org/2000/svg";

function xAt(i: number): number {
  const m = MEANDER[((i % MEANDER.length) + MEANDER.length) % MEANDER.length];
  return 64 + m;
}
function yAt(i: number): number {
  return PAD_Y + i * ROW_H + ROW_H / 2;
}
function routeHeight(count: number): number {
  return PAD_Y * 2 + Math.max(count, 1) * ROW_H;
}

interface PaneData {
  stationEls: Map<string, HTMLElement>;
  order: string[] | null;
  selected: string | null;
  nameCursor: number;
}

function pane(client: RigClient): PaneData {
  return client.data as unknown as PaneData;
}
function unquote(raw: string): string {
  return raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')
    ? raw.slice(1, -1)
    : raw;
}
function okValue<T>(result: unknown): T {
  return (result as { 0: T })[0];
}
function values(client: RigClient): string[] {
  return watershed
    .sequence_values(client.handle)
    .toArray()
    .map((v: unknown) => unquote(json.to_string(v)));
}

export function initSequenceDemo() {
  let rig: ReturnType<typeof createSluiceRig> = null;
  let notes: RigNotes | null = null;
  // True while a local edit's synchronous render runs, so the field-notes
  // flash is magenta on the origin and ink on sequenced deliveries.
  let submitting = false;

  function nextName(client: RigClient): string {
    const data = pane(client);
    const visible = new Set(values(client));
    for (let i = 0; i < SPARE_NAMES.length; i++) {
      const name = SPARE_NAMES[data.nameCursor % SPARE_NAMES.length];
      data.nameCursor += CLIENT_IDS.length;
      if (!visible.has(name)) return name;
    }
    return SPARE_NAMES[pane(client).nameCursor % SPARE_NAMES.length];
  }

  function submitOp(
    client: RigClient,
    marker: string | null,
    write: () => void,
    label: string,
  ) {
    if (!rig) return;
    submitting = true;
    try {
      rig.submit(client, marker, write, label);
    } finally {
      submitting = false;
    }
  }

  // ── local edits (indexes validated against the caller's optimistic list) ──
  function localInsert(clientId: string, index: number) {
    if (!rig) return;
    const client = rig.clients[clientId];
    const at = Math.max(0, Math.min(index, values(client).length));
    const name = nextName(client);
    submitOp(
      client,
      "st:" + name,
      () => {
        watershed.sequence_insert(client.handle, at, json.string(name));
      },
      `insert ${name} @${at + 1}`,
    );
  }

  function localMove(clientId: string, from: number, to: number, name: string) {
    if (!rig) return;
    const client = rig.clients[clientId];
    const len = values(client).length;
    // lattice contract: `to` is evaluated after removing the item at `from`,
    // so its valid range is 0..len-1 (the shortened list has len-1 items).
    if (from < 0 || from >= len || to < 0 || to > len - 1) return;
    submitOp(
      client,
      "st:" + name,
      () => {
        watershed.sequence_move(client.handle, from, to);
      },
      `move ${name} ${from + 1}→${to + 1}`,
    );
  }

  function localRename(clientId: string, index: number, oldName: string) {
    if (!rig) return;
    const client = rig.clients[clientId];
    if (index < 0 || index >= values(client).length) return;
    const name = nextName(client);
    const data = pane(client);
    if (data.selected === oldName) data.selected = name;
    submitOp(
      client,
      "st:" + name,
      () => {
        watershed.sequence_replace(client.handle, index, json.string(name));
      },
      `rename ${oldName} → ${name}`,
    );
  }

  function localDelete(clientId: string, index: number, name: string) {
    if (!rig) return;
    const client = rig.clients[clientId];
    if (index < 0 || index >= values(client).length) return;
    pane(client).selected = null;
    submitOp(
      client,
      null,
      () => {
        watershed.sequence_delete(client.handle, index);
      },
      `delete ${name} @${index + 1}`,
    );
  }

  // ── rendering ─────────────────────────────────────────────────────────────
  function drawRiver(routeEl: HTMLElement, count: number) {
    let svg = routeEl.querySelector("svg.route-river");
    if (!(svg instanceof SVGSVGElement)) {
      svg = document.createElementNS(SVG_NS, "svg");
      svg.classList.add("route-river");
      svg.setAttribute("aria-hidden", "true");
      svg.append(document.createElementNS(SVG_NS, "path"));
      routeEl.prepend(svg);
    }
    const path = svg.querySelector("path");
    if (!path) return;
    // A smooth meander through every station point, extended one step above
    // the first and below the last so the river runs off the pane.
    const pts: Array<[number, number]> = [];
    for (let i = -1; i <= count; i++) pts.push([xAt(i), yAt(i)]);
    let d = `M ${pts[0][0]} ${pts[0][1]}`;
    for (let i = 1; i < pts.length - 1; i++) {
      const mx = (pts[i][0] + pts[i + 1][0]) / 2;
      const my = (pts[i][1] + pts[i + 1][1]) / 2;
      d += ` Q ${pts[i][0]} ${pts[i][1]} ${mx} ${my}`;
    }
    const last = pts[pts.length - 1];
    d += ` L ${last[0]} ${last[1]}`;
    path.setAttribute("d", d);
  }

  function buildStation(client: RigClient, name: string): HTMLElement {
    const st = document.createElement("div");
    st.className = "station";
    const dot = document.createElement("span");
    dot.className = "station-dot";
    dot.setAttribute("aria-hidden", "true");
    const no = document.createElement("span");
    no.className = "station-no annot";
    no.setAttribute("data-station-no", "");
    const label = document.createElement("button");
    label.type = "button";
    label.className = "station-name";
    label.textContent = name;
    label.setAttribute(
      "aria-label",
      `Select ${name} on ${CLIENT_LABEL[client.id]}`,
    );
    label.addEventListener("click", () => {
      const data = pane(client);
      data.selected = data.selected === name ? null : name;
      renderRoute(client);
    });
    st.append(dot, no, label);
    return st;
  }

  function rebuildGaps(client: RigClient, routeEl: HTMLElement, count: number) {
    for (const gap of routeEl.querySelectorAll(".gap")) gap.remove();
    for (let i = 0; i <= count; i++) {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "gap";
      btn.textContent = "+";
      btn.setAttribute(
        "aria-label",
        `Insert a waypoint at position ${i + 1} on ${CLIENT_LABEL[client.id]}`,
      );
      btn.title = `Insert a waypoint at position ${i + 1}`;
      const x = (xAt(i - 1) + xAt(i)) / 2;
      const y = PAD_Y + i * ROW_H;
      btn.style.transform = `translate(${x - 10}px, ${y - 10}px)`;
      btn.addEventListener("click", () => localInsert(client.id, i));
      routeEl.append(btn);
    }
  }

  function updateActionBar(client: RigClient, names: string[]) {
    const bar = client.el.querySelector("[data-route-actions]");
    if (!bar) return;
    const data = pane(client);
    const i = data.selected == null ? -1 : names.indexOf(data.selected);
    for (const btn of bar.querySelectorAll("button[data-act]")) {
      if (!(btn instanceof HTMLButtonElement)) continue;
      const act = btn.getAttribute("data-act");
      btn.disabled =
        i < 0 ||
        (act === "up" && i === 0) ||
        (act === "down" && i === names.length - 1);
    }
    const label = bar.querySelector("[data-selected]");
    if (label) label.textContent = data.selected ?? "select a station";
  }

  function renderRoute(client: RigClient) {
    const routeEl = client.el.querySelector("[data-route]");
    if (!(routeEl instanceof HTMLElement)) return;
    const data = pane(client);
    const prev = data.order;
    const names = values(client);
    if (data.selected != null && !names.includes(data.selected))
      data.selected = null;

    routeEl.style.height = `${routeHeight(names.length)}px`;
    drawRiver(routeEl, names.length);

    const seen = new Set<string>();
    names.forEach((name, i) => {
      seen.add(name);
      let st = data.stationEls.get(name);
      if (!st) {
        st = buildStation(client, name);
        data.stationEls.set(name, st);
        routeEl.append(st);
      }
      st.style.transform = `translate(${xAt(i) - 8}px, ${yAt(i) - 8}px)`;
      const no = st.querySelector("[data-station-no]");
      if (no) no.textContent = String(i + 1);
      st.classList.toggle("pending", client.pending.includes("st:" + name));
      st.classList.toggle("selected", data.selected === name);
    });
    for (const [name, el] of data.stationEls) {
      if (!seen.has(name)) {
        el.remove();
        data.stationEls.delete(name);
      }
    }
    rebuildGaps(client, routeEl, names.length);
    updateActionBar(client, names);

    const badge = client.el.querySelector("[data-pending-count]");
    if (badge instanceof HTMLElement) {
      badge.textContent = `${client.pending.length} pending`;
      badge.classList.toggle("is-pending", client.pending.length > 0);
    }

    data.order = names;
    // Field notes: flash every position whose value changed — magenta on the
    // origin's optimistic render, ink as a sequenced op lands on a replica.
    if (notes?.active && prev != null) {
      const changed = names
        .map((name, i) => (prev[i] !== name ? data.stationEls.get(name) : null))
        .filter((el): el is HTMLElement => el != null);
      notes.flashEls(changed, submitting);
    }
  }

  rig = createSluiceRig({
    rig: "[data-route-rig]",
    status: "[data-route-status]",
    section: "#route-demo",
    control: "route",
    document: "sequence-demo",
    clientIds: CLIENT_IDS,
    clientLabel: CLIENT_LABEL,
    setup: (clients, server) => {
      // One client creates the sequence, attaches it under the root map, and
      // seeds the initial route; the others resolve the shared handle. All of
      // this drains inside setup's settle, so the visible timeline is clean.
      const a = clients["a"];
      const seq = okValue<unknown>(watershed.create_sequence(a.doc));
      a.handle = seq;
      const runtimeA = watershed.runtime_of(a.doc);
      runtime.set(
        runtimeA,
        "root",
        SEQ_ADDRESS,
        watershed.sequence_handle_of(seq),
      );
      INITIAL_ROUTE.forEach((name, i) => {
        watershed.sequence_insert(seq, i, json.string(name));
      });
      sluice.settle(server);
      CLIENT_IDS.forEach((id, i) => {
        const client = clients[id];
        if (id !== "a") {
          const rt = watershed.runtime_of(client.doc);
          const stored = some<unknown>(runtime.get(rt, "root", SEQ_ADDRESS));
          client.handle = okValue<unknown>(
            watershed.resolve_sequence(client.doc, stored),
          );
        }
        client.data = {
          stationEls: new Map(),
          order: null,
          selected: null,
          nameCursor: i,
        } as unknown as Record<string, unknown>;
        // Reset re-runs setup against panes that still hold old station DOM.
        client.el.querySelector("[data-route]")?.replaceChildren();
      });
    },
    render: renderRoute,
    canonical: (client) => JSON.stringify(values(client)),
  });
  if (!rig) return;

  const rigEl = document.querySelector("[data-route-rig]");
  const noteToggle = document.querySelector("[data-route-notes]");
  const noteEl = document.querySelector("[data-route-note]");
  if (
    rigEl &&
    noteToggle instanceof HTMLInputElement &&
    noteEl instanceof HTMLElement
  ) {
    notes = createRigNotes({
      rig: rigEl,
      toggle: noteToggle,
      note: noteEl,
      caption:
        "SharedSequence — items keep identity, so concurrent inserts, moves, and deletes merge instead of fighting over index numbers. Watch a station flash magenta the moment a client edits the route, then ink on every replica as the op is sequenced and applied; the newest log line boxes as each op lands.",
    });
  }

  // Per-pane action bar: acts on that pane's selected station.
  for (const id of CLIENT_IDS) {
    const client = rig.clients[id];
    const bar = client.el.querySelector("[data-route-actions]");
    if (!bar) continue;
    bar.addEventListener("click", (event) => {
      const btn =
        event.target instanceof Element
          ? event.target.closest("button[data-act]")
          : null;
      if (!(btn instanceof HTMLButtonElement) || btn.disabled) return;
      const data = pane(client);
      if (data.selected == null) return;
      const names = values(client);
      const i = names.indexOf(data.selected);
      if (i < 0) return;
      switch (btn.getAttribute("data-act")) {
        case "up":
          localMove(id, i, i - 1, data.selected);
          break;
        case "down":
          localMove(id, i, i + 1, data.selected);
          break;
        case "rename":
          localRename(id, i, data.selected);
          break;
        case "delete":
          localDelete(id, i, data.selected);
          break;
      }
    });
  }

  // Race a move: B and C move the same waypoint opposite ways, concurrently.
  document.querySelector("[data-route-race-move]")?.addEventListener("click", () => {
    if (!rig) return;
    const bNames = values(rig.clients["b"]);
    const cNames = values(rig.clients["c"]);
    for (const name of bNames) {
      const iB = bNames.indexOf(name);
      const iC = cNames.indexOf(name);
      if (iB > 0 && iC >= 0 && iC < cNames.length - 1) {
        localMove("b", iB, iB - 1, name);
        localMove("c", iC, iC + 1, name);
        return;
      }
    }
  });

  // Crowd an insert: B and C insert different waypoints at the same position.
  document
    .querySelector("[data-route-race-insert]")
    ?.addEventListener("click", () => {
      if (!rig) return;
      localInsert("b", Math.min(2, values(rig.clients["b"]).length));
      localInsert("c", Math.min(2, values(rig.clients["c"]).length));
    });

  document.querySelector("[data-route-reset]")?.addEventListener("click", () => rig?.reset());
}
