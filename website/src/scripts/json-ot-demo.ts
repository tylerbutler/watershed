// Live JSON-OT convergence demo: three real watershed documents share one
// json0 document, driven through the in-memory sluice (see ./demo/sluice-rig.ts
// for the shared orchestration). Unlike the CRDTs, json0 *transforms*: the
// runtime keeps at most one op in flight (the Wave/ShareDB client model),
// rebases it past concurrent remote ops, and transforms inbound ops into head
// context — concurrent list inserts at the same index are the star.
//
// json0 isn't in the JS facade yet, so this drives the runtime (`runtime_js`)
// directly: one client creates the channel, seeds the baseline into it while
// detached, attaches it under the root map (the snapshot rides along), and the
// others resolve the handle. Edits are then ordinary `submit_json_ot` calls the
// sluice sequences; the runtime owns the transform/inflight/buffer machinery.
import * as watershed from "../../../build/dev/javascript/watershed/watershed_js.mjs";
import * as runtime from "../../../build/dev/javascript/watershed/watershed/runtime_js.mjs";
import * as jsonOt from "../../../build/dev/javascript/watershed/watershed/json_ot.mjs";
import * as handle from "../../../build/dev/javascript/watershed/watershed/handle.mjs";
import * as sluice from "../../../build/dev/javascript/watershed/watershed/sluice_js.mjs";
import { toList } from "../../../build/dev/javascript/watershed/gleam.mjs";
import { createSluiceRig, some, type RigClient } from "./demo/sluice-rig.ts";

const S = (s: string) => new jsonOt.VString(s);
const N = (n: number) => new jsonOt.VNumber(new jsonOt.NInt(n));
const K = (k: string) => new jsonOt.Key(k);
const IDX = (i: number) => new jsonOt.Index(i);
const path = (...keys: unknown[]) => toList(keys);
const op = (...components: unknown[]) => toList(components);

function vArray(values: string[]) {
  return new jsonOt.VArray(toList(values.map(S)));
}
function vObject(pairs: Array<[string, unknown]>) {
  const sorted = [...pairs].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  return new jsonOt.VObject(toList(sorted.map(([k, v]) => [k, v])));
}

const CREW_BASE = ["Ada", "Ben"];
const SITE_BASE = "Mill Race";
const STAGE_BASE = 24;
const TREND_BASE = "steady";
const NEW_NAMES = ["Cy", "Dot", "Eli", "Fen", "Gus", "Hana", "Ime", "Jo"];
const SITE_NAMES = ["Mill Race", "Kettle Run", "Low Ford", "Spillway Gate"];
const TREND_NAMES = ["rising", "cresting", "falling", "steady"];
const DOC_KEY = "doc"; // root-map key holding the shared json0 handle

const CLIENT_IDS = ["a", "b", "c"];
const CLIENT_LABEL: Record<string, string> = {
  a: "Client A",
  b: "Client B",
  c: "Client C",
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function toPlain(v: any): any {
  if (v instanceof jsonOt.VNull) return null;
  if (v instanceof jsonOt.VBool) return v[0];
  if (v instanceof jsonOt.VNumber) return v[0][0];
  if (v instanceof jsonOt.VString) return v[0];
  if (v instanceof jsonOt.VArray) return v[0].toArray().map(toPlain);
  if (v instanceof jsonOt.VObject) {
    const out: Record<string, unknown> = {};
    for (const [k, val] of v[0].toArray()) out[k] = toPlain(val);
    return out;
  }
  return null;
}

interface Handle {
  runtime: unknown;
  address: string;
}
function h(client: RigClient): Handle {
  return client.handle as Handle;
}
function okValue<T>(result: unknown): T {
  return (result as { 0: T })[0];
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function optimistic(client: RigClient): any {
  const hd = h(client);
  const view = some<unknown>(runtime.json_ot_view(hd.runtime, hd.address));
  return view == null ? null : toPlain(view);
}

export function initJsonOtDemo() {
  let rig: ReturnType<typeof createSluiceRig> = null;

  function cursors(client: RigClient) {
    return client.data as { name: number; site: number; trend: number };
  }

  function submit(client: RigClient, marker: string, components: unknown, label: string) {
    if (!rig) return;
    const hd = h(client);
    rig.submit(
      client,
      marker,
      () => runtime.submit_json_ot(hd.runtime, hd.address, components),
      label,
    );
  }

  function localStage(clientId: string, delta: number) {
    if (!rig) return;
    const client = rig.clients[clientId];
    const sign = delta > 0 ? "+" : "";
    submit(
      client,
      "field:gauge.stage",
      op(jsonOt.number_add(path(K("gauge"), K("stage")), new jsonOt.NInt(delta))),
      `add .gauge.stage ${sign}${delta}`,
    );
  }
  function localTrend(clientId: string) {
    if (!rig) return;
    const client = rig.clients[clientId];
    const current = optimistic(client).gauge.trend;
    const c = cursors(client);
    const next = TREND_NAMES[c.trend % TREND_NAMES.length];
    c.trend += 1;
    if (next === current) return localTrend(clientId);
    submit(
      client,
      "field:gauge.trend",
      op(jsonOt.obj_replace(path(K("gauge"), K("trend")), S(current), S(next))),
      `set .gauge.trend "${next}"`,
    );
  }
  function localSite(clientId: string) {
    if (!rig) return;
    const client = rig.clients[clientId];
    const current = optimistic(client).site;
    const c = cursors(client);
    const next = SITE_NAMES[c.site % SITE_NAMES.length];
    c.site += 1;
    if (next === current) return localSite(clientId);
    submit(
      client,
      "field:site",
      op(jsonOt.obj_replace(path(K("site")), S(current), S(next))),
      `set .site "${next}"`,
    );
  }
  function localCrewAdd(clientId: string) {
    if (!rig) return;
    const client = rig.clients[clientId];
    const c = cursors(client);
    const name = NEW_NAMES[c.name % NEW_NAMES.length];
    c.name += 1;
    submit(
      client,
      "field:crew",
      op(jsonOt.list_insert(path(K("crew"), IDX(0)), S(name))),
      `insert .crew[0] "${name}"`,
    );
  }
  function localCrewDelete(clientId: string, index: number) {
    if (!rig) return;
    const client = rig.clients[clientId];
    const name = optimistic(client).crew[index];
    submit(
      client,
      "field:crew",
      op(jsonOt.list_delete(path(K("crew"), IDX(index)), S(name))),
      `delete .crew[${index}] "${name}"`,
    );
  }
  function localCrewMove(clientId: string, index: number) {
    if (!rig) return;
    const client = rig.clients[clientId];
    submit(
      client,
      "field:crew",
      op(jsonOt.list_move(path(K("crew"), IDX(index)), index - 1)),
      `move .crew[${index}] → ${index - 1}`,
    );
  }

  function pendingField(client: RigClient, field: string): boolean {
    return client.pending.includes("field:" + field);
  }

  function render(client: RigClient) {
    const opt = optimistic(client);
    if (!opt) return;
    const el = client.el;

    const setField = (field: string, value: unknown) => {
      const node = el.querySelector(`[data-field='${field}'] [data-value]`);
      if (node) {
        node.textContent = String(value);
        node.classList.toggle("pending", pendingField(client, field));
      }
    };
    setField("site", opt.site);
    setField("gauge.stage", opt.gauge.stage);
    setField("gauge.trend", opt.gauge.trend);

    const crewEl = el.querySelector("[data-crew]");
    if (crewEl) {
      crewEl.replaceChildren();
      const crewPending = pendingField(client, "crew");
      opt.crew.forEach((name: string, index: number) => {
        const li = document.createElement("li");
        li.className = crewPending ? "chip pending" : "chip";
        const openQuote = document.createElement("span");
        openQuote.className = "jp";
        openQuote.textContent = '"';
        const label = document.createElement("span");
        label.className = "chip-name";
        label.textContent = name;
        const closeQuote = document.createElement("span");
        closeQuote.className = "jp";
        closeQuote.textContent = index < opt.crew.length - 1 ? '",' : '"';
        li.append(openQuote, label, closeQuote);

        const actions = document.createElement("span");
        actions.className = "chip-actions";
        if (index > 0) {
          const up = document.createElement("button");
          up.type = "button";
          up.textContent = "↑";
          up.setAttribute("aria-label", `Move ${name} up on ${CLIENT_LABEL[client.id]}`);
          up.addEventListener("click", () => localCrewMove(client.id, index));
          actions.append(up);
        }
        const del = document.createElement("button");
        del.type = "button";
        del.className = "chip-del";
        del.textContent = "×";
        del.setAttribute("aria-label", `Remove ${name} from crew on ${CLIENT_LABEL[client.id]}`);
        del.addEventListener("click", () => localCrewDelete(client.id, index));
        actions.append(del);
        li.append(actions);
        crewEl.append(li);
      });
    }

    const count = client.pending.length;
    const badge = el.querySelector("[data-pending-count]");
    if (badge instanceof HTMLElement) {
      badge.textContent = `${count} pending`;
      badge.classList.toggle("is-pending", count > 0);
    }
  }

  function seedInto(rt: unknown, address: string) {
    runtime.submit_json_ot(
      rt,
      address,
      op(
        jsonOt.obj_insert(path(K("crew")), vArray(CREW_BASE)),
        jsonOt.obj_insert(
          path(K("gauge")),
          vObject([
            ["stage", N(STAGE_BASE)],
            ["trend", S(TREND_BASE)],
          ]),
        ),
        jsonOt.obj_insert(path(K("site")), S(SITE_BASE)),
      ),
    );
  }

  rig = createSluiceRig({
    rig: "[data-jot-rig]",
    status: "[data-jot-status]",
    section: "#jot-demo",
    control: "jot",
    document: "json-ot-demo",
    clientIds: CLIENT_IDS,
    clientLabel: CLIENT_LABEL,
    setup: (clients, server) => {
      const a = clients["a"];
      const rtA = watershed.runtime_of(a.doc);
      const address = okValue<string>(runtime.create_json_ot(rtA));
      // Seed the baseline while the channel is detached; the snapshot rides the
      // attach op, so late joiners bootstrap from it.
      seedInto(rtA, address);
      runtime.set(rtA, "root", DOC_KEY, handle.encode_handle(address));
      a.handle = { runtime: rtA, address };
      a.data = { name: 0, site: 0, trend: 0 };
      sluice.settle(server);
      CLIENT_IDS.slice(1).forEach((id) => {
        const client = clients[id];
        const rt = watershed.runtime_of(client.doc);
        const stored = some<unknown>(runtime.get(rt, "root", DOC_KEY));
        const addr = okValue<string>(handle.parse_handle(stored));
        runtime.resolve_address(rt, addr);
        client.handle = { runtime: rt, address: addr };
        client.data = { name: 0, site: 0, trend: 0 };
      });
    },
    render,
    canonical: (client) => JSON.stringify(optimistic(client)),
  });
  if (!rig) return;

  for (const id of CLIENT_IDS) {
    const el = rig.clients[id].el;
    el.querySelector("[data-stage-inc]")?.addEventListener("click", () => localStage(id, 1));
    el.querySelector("[data-stage-dec]")?.addEventListener("click", () => localStage(id, -1));
    el.querySelector("[data-site-cycle]")?.addEventListener("click", () => localSite(id));
    el.querySelector("[data-trend-cycle]")?.addEventListener("click", () => localTrend(id));
    el.querySelector("[data-crew-add]")?.addEventListener("click", () => localCrewAdd(id));
  }

  document.querySelector("[data-jot-race]")?.addEventListener("click", () => {
    localCrewAdd("a");
    localCrewAdd("b");
  });
  document.querySelector("[data-jot-reset]")?.addEventListener("click", () => rig?.reset());
}
