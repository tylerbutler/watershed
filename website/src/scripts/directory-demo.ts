// Live SharedDirectory convergence demo: three real watershed documents share
// one nested folder tree, driven through the in-memory sluice (see
// ./demo/sluice-rig.ts for the shared orchestration). SharedDirectory isn't in
// the JS facade yet, so this drives the runtime (`runtime_js`) directly: one
// client creates the directory and attaches it under the root map; the others
// resolve the handle. From there, folder/reading edits are ordinary runtime
// calls the sluice sequences — the runtime owns optimistic apply, pending, and
// resubmit, so the demo just issues edits and reads the tree back.
import * as watershed from "../../../build/dev/javascript/watershed/watershed_js.mjs";
import * as runtime from "../../../build/dev/javascript/watershed/watershed/runtime_js.mjs";
import * as handle from "../../../build/dev/javascript/watershed/watershed/handle.mjs";
import * as sluice from "../../../build/dev/javascript/watershed/watershed/sluice_js.mjs";
import * as json from "../../../build/dev/javascript/gleam_json/gleam/json.mjs";
import { createSluiceRig, some, type RigClient } from "./demo/sluice-rig.ts";

const CLIENT_IDS = ["a", "b", "c"];
const CLIENT_LABEL: Record<string, string> = {
  a: "Client A",
  b: "Client B",
  c: "Client C",
};
const FOLDER_NAMES = [
  "surveys", "plans", "logs", "spoil", "borrow-pit", "wash-fill",
  "intake", "weir", "kettle-run", "mill-race",
];
const READINGS: Array<[string, string]> = [
  ["BM-17", "recorded"], ["grade", "2.1%"], ["silt", "high"], ["stage", "24"],
  ["flow", "61"], ["BM-22", "recorded"], ["datum", "set"],
];
const RACE_FOLDER = "kettle-run";
const DIR_ADDRESS = "tree"; // root-map key holding the shared directory handle

interface Handle {
  runtime: unknown;
  address: string;
}

function join(path: string, name: string): string {
  return path === "/" ? "/" + name : path + "/" + name;
}
function parentOf(path: string): string {
  const at = path.lastIndexOf("/");
  return at <= 0 ? "/" : path.slice(0, at);
}
function baseName(path: string): string {
  return path.slice(path.lastIndexOf("/") + 1);
}
function unquote(raw: string): string {
  return raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"') ? raw.slice(1, -1) : raw;
}
function okValue<T>(result: unknown): T {
  return (result as { 0: T })[0];
}

function h(client: RigClient): Handle {
  return client.handle as Handle;
}
function subdirs(client: RigClient, path: string): string[] {
  const hd = h(client);
  return runtime.directory_subdirectories(hd.runtime, hd.address, path).toArray();
}
function entries(client: RigClient, path: string): Array<[string, string]> {
  const hd = h(client);
  return runtime
    .directory_entries(hd.runtime, hd.address, path)
    .toArray()
    .map(([key, value]: [string, unknown]) => [key, unquote(json.to_string(value))]);
}

function canonicalTree(client: RigClient, path: string): unknown {
  const keys = entries(client, path).sort((a, b) => (a[0] < b[0] ? -1 : 1));
  const children = subdirs(client, path).slice().sort();
  return { keys, subs: children.map((name) => [name, canonicalTree(client, join(path, name))]) };
}

export function initDirectoryDemo() {
  let rig: ReturnType<typeof createSluiceRig> = null;

  function nextFolder(client: RigClient, path: string): string {
    const siblings = new Set(subdirs(client, path));
    const data = client.data as { folderCursor: number };
    for (let i = 0; i < FOLDER_NAMES.length; i++) {
      const name = FOLDER_NAMES[data.folderCursor % FOLDER_NAMES.length];
      data.folderCursor += CLIENT_IDS.length;
      if (!siblings.has(name)) return name;
    }
    return FOLDER_NAMES[data.folderCursor % FOLDER_NAMES.length];
  }
  function nextReading(client: RigClient): [string, string] {
    const data = client.data as { readingCursor: number };
    const reading = READINGS[data.readingCursor % READINGS.length];
    data.readingCursor += 1;
    return reading;
  }

  function localCreate(clientId: string, path: string, forcedName?: string) {
    if (!rig) return;
    const client = rig.clients[clientId];
    const name = forcedName ?? nextFolder(client, path);
    const childPath = join(path, name);
    const hd = h(client);
    rig.submit(
      client,
      "sub:" + childPath,
      () => runtime.directory_create_subdirectory(hd.runtime, hd.address, path, name),
      `mkdir ${childPath}`,
    );
  }
  function localSet(clientId: string, path: string, forced?: [string, string]) {
    if (!rig) return;
    const client = rig.clients[clientId];
    const [key, value] = forced ?? nextReading(client);
    const hd = h(client);
    rig.submit(
      client,
      `key:${path}::${key}`,
      () => runtime.directory_set(hd.runtime, hd.address, path, key, json.string(value)),
      `set ${path} · ${key}`,
    );
  }
  function localDelete(clientId: string, path: string) {
    if (!rig) return;
    const client = rig.clients[clientId];
    const hd = h(client);
    rig.submit(
      client,
      "del:" + path,
      () =>
        runtime.directory_delete_subdirectory(hd.runtime, hd.address, parentOf(path), baseName(path)),
      `rmdir ${path}`,
    );
  }

  function actionBtn(text: string, aria: string, onClick: () => void, extraClass = ""): HTMLButtonElement {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "node-action" + (extraClass ? " " + extraClass : "");
    btn.textContent = text;
    btn.setAttribute("aria-label", aria);
    btn.addEventListener("click", onClick);
    return btn;
  }

  function renderNode(client: RigClient, path: string, isRoot: boolean): Element {
    const node = document.createElement("div");
    node.className = "dir-node";
    const head = document.createElement("div");
    head.className = "dir-head";
    if (!isRoot && client.pending.includes("sub:" + path)) head.classList.add("pending");

    const label = document.createElement("span");
    label.className = "dir-name";
    label.textContent = isRoot ? "/" : baseName(path) + "/";
    head.append(label);

    const actions = document.createElement("span");
    actions.className = "dir-actions";
    actions.append(
      actionBtn("+ folder", `Add a folder under ${path} on ${CLIENT_LABEL[client.id]}`, () =>
        localCreate(client.id, path)),
      actionBtn("+ reading", `Add a reading in ${path} on ${CLIENT_LABEL[client.id]}`, () =>
        localSet(client.id, path)),
    );
    if (!isRoot) {
      actions.append(
        actionBtn("×", `Delete ${path} on ${CLIENT_LABEL[client.id]}`, () =>
          localDelete(client.id, path), "dir-del"),
      );
    }
    head.append(actions);
    node.append(head);

    const keys = entries(client, path);
    if (keys.length) {
      const dl = document.createElement("ul");
      dl.className = "dir-keys";
      for (const [key, value] of keys) {
        const li = document.createElement("li");
        li.className = "dir-key";
        if (client.pending.includes(`key:${path}::${key}`)) li.classList.add("pending");
        const k = document.createElement("span");
        k.className = "dk-key";
        k.textContent = key;
        const v = document.createElement("span");
        v.className = "dk-val";
        v.textContent = value;
        li.append(k, v);
        dl.append(li);
      }
      node.append(dl);
    }

    const children = subdirs(client, path);
    if (children.length) {
      const childWrap = document.createElement("div");
      childWrap.className = "dir-children";
      for (const name of children) childWrap.append(renderNode(client, join(path, name), false));
      node.append(childWrap);
    }
    return node;
  }

  function renderTree(client: RigClient) {
    const treeEl = client.el.querySelector("[data-tree]");
    if (!treeEl) return;
    treeEl.replaceChildren(renderNode(client, "/", true));
    const badge = client.el.querySelector("[data-pending-count]");
    if (badge instanceof HTMLElement) {
      badge.textContent = `${client.pending.length} pending`;
      badge.classList.toggle("is-pending", client.pending.length > 0);
    }
  }

  rig = createSluiceRig({
    rig: "[data-dir-rig]",
    status: "[data-dir-status]",
    section: "#dir-demo",
    control: "dir",
    document: "directory-demo",
    clientIds: CLIENT_IDS,
    clientLabel: CLIENT_LABEL,
    setup: (clients, server) => {
      // One client creates the directory and attaches it under the root map;
      // the others resolve the shared handle once the attach has propagated.
      const a = clients["a"];
      const runtimeA = watershed.runtime_of(a.doc);
      const address = okValue<string>(runtime.create_directory(runtimeA));
      runtime.set(runtimeA, "root", DIR_ADDRESS, handle.encode_handle(address));
      a.handle = { runtime: runtimeA, address };
      a.data = { folderCursor: 0, readingCursor: 0 };
      sluice.settle(server);
      CLIENT_IDS.slice(1).forEach((id, i) => {
        const client = clients[id];
        const rt = watershed.runtime_of(client.doc);
        const stored = some<unknown>(runtime.get(rt, "root", DIR_ADDRESS));
        const addr = okValue<string>(handle.parse_handle(stored));
        runtime.resolve_address(rt, addr);
        client.handle = { runtime: rt, address: addr };
        client.data = { folderCursor: i + 1, readingCursor: i + 1 };
      });
    },
    render: renderTree,
    canonical: (client) => JSON.stringify(canonicalTree(client, "/")),
  });
  if (!rig) return;

  document.querySelector("[data-dir-race]")?.addEventListener("click", () => {
    for (const id of CLIENT_IDS) localCreate(id, "/", RACE_FOLDER);
  });
  document.querySelector("[data-dir-seed]")?.addEventListener("click", () => {
    localCreate("a", "/", "surveys");
    localSet("a", "/surveys", ["BM-17", "recorded"]);
    localCreate("a", "/", "plans");
    localSet("a", "/plans", ["grade", "2.1%"]);
    const data = rig!.clients["a"].data as { folderCursor: number; readingCursor: number };
    data.folderCursor += 2;
    data.readingCursor += 2;
  });
  document.querySelector("[data-dir-reset]")?.addEventListener("click", () => rig?.reset());
}
