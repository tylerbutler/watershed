import { Error, Ok } from "../../gleam.mjs";
import { register } from "../../../watershed_lustre/watershed_lustre/textarea_element.mjs";

const bridges = new WeakMap();

function message(error) {
  return error instanceof globalThis.Error ? error.message : String(error);
}

function cursor(payload) {
  return payload === "" ? null : JSON.parse(payload);
}

function peer(id, label, colour, payload) {
  const value = cursor(payload);
  return value == null ? [] : [{ id, label, colour, cursor: value }];
}

function connect(element, callbacks) {
  const bridge = { callbacks };
  element.addEventListener("change", () => bridge.callbacks.onChange());
  element.addEventListener("cursor", (event) => {
    bridge.callbacks.onCursor(JSON.stringify(event.detail ?? null));
  });
  element.addEventListener("error", (event) => {
    bridge.callbacks.onError(event.detail?.message ?? "");
  });
  bridges.set(element, bridge);
  return bridge;
}

export function syncEditors(
  root,
  channelA,
  channelB,
  cursorA,
  cursorB,
  onChangeA,
  onChangeB,
  onCursorA,
  onCursorB,
  onErrorA,
  onErrorB,
) {
  try {
    if (!customElements.get("watershed-textarea")) register();
    const editorA = root.querySelector('[data-pane="a"] watershed-textarea');
    const editorB = root.querySelector('[data-pane="b"] watershed-textarea');
    if (!(editorA instanceof HTMLElement) || !(editorB instanceof HTMLElement)) {
      throw new globalThis.Error("Cannot find the text editors.");
    }

    const bridgeA =
      bridges.get(editorA) ??
      connect(editorA, { onChange: onChangeA, onCursor: onCursorA, onError: onErrorA });
    const bridgeB =
      bridges.get(editorB) ??
      connect(editorB, { onChange: onChangeB, onCursor: onCursorB, onError: onErrorB });
    bridgeA.callbacks = {
      onChange: onChangeA,
      onCursor: onCursorA,
      onError: onErrorA,
    };
    bridgeB.callbacks = {
      onChange: onChangeB,
      onCursor: onCursorB,
      onError: onErrorB,
    };

    const styles = getComputedStyle(document.documentElement);
    editorA.channel = channelA;
    editorB.channel = channelB;
    editorA.peers = peer(
      "b",
      "Client B",
      styles.getPropertyValue("--waterline").trim() || "#2563eb",
      cursorA,
    );
    editorB.peers = peer(
      "a",
      "Client A",
      styles.getPropertyValue("--overprint-deep").trim() || "#c81e78",
      cursorB,
    );
    return new Ok(undefined);
  } catch (error) {
    return new Error(message(error));
  }
}
