// Reusable bridge between a Quill-compatible editor and Watershed's
// SharedRichText callbacks. This module is dependency-free (no Quill import)
// so it can be unit-tested with a fake editor and Node's built-in test runner.
// The rich-text demo wires an actual Quill instance plus the generated
// `rich_text`/`rich_text_kernel` bindings through the injected callbacks below.
//
// The adapter never hard-codes a generated Gleam module path: conversion,
// submission, and transform behaviour all arrive as plain functions in
// `config`, so this file stays reusable across demos and testable without a
// build.

/**
 * A normalized cursor/selection range, independent of Quill's `Range` class.
 * @typedef {Object} RichTextSelection
 * @property {number} index
 * @property {number} length
 */

/**
 * One entry in the peer-selection cache: a stable peer/user id plus their
 * last-known selection and optional display metadata (name, color, ...).
 * Consumers may attach any extra fields; the adapter passes them through
 * unmodified (shallow-cloned) alongside `selection`.
 *
 * `id` may be a `string` or `number`, but is canonicalized (see
 * `canonicalId`) for cache keys and author-identity comparisons so that,
 * e.g., peer id `1` and author id `"1"` are treated as the same peer. The
 * original `id` value supplied here is preserved on cached/snapshotted
 * entries for display.
 * @typedef {Object} PeerSelectionEntry
 * @property {string|number} id
 * @property {RichTextSelection|null} selection
 * @property {string} [name]
 * @property {string} [color]
 */

/**
 * The shape the caller uses to hand the adapter a RichText change event
 * (e.g. from `rich_text_kernel.RichTextChanged`), without coupling this
 * module to that generated type.
 * @typedef {Object} RichTextChangeEvent
 * @property {unknown} delta - Quill-style delta (e.g. `{ops: [...]}`).
 * @property {boolean} local - `true` for the optimistic echo of our own
 *   submitted edit; `false` for a genuine remote change.
 * @property {string|number} [author] - Peer/user id who authored a remote
 *   change, when known. Compared against cached peer ids via `canonicalId`
 *   (so `1` and `"1"` match). Omit or leave `undefined` when the author
 *   isn't available (e.g. anonymous broadcast); the adapter then treats
 *   every cached peer as remote and relies on the next heartbeat to
 *   reconcile.
 * @property {boolean} [authorSelectionAlreadyApplied] - `true` when the
 *   caller's own presence/roster path has *already* delivered `author`'s
 *   post-edit selection to every peer's cache by the time this delta
 *   arrives here — e.g. a synchronous, zero-latency presence broadcast
 *   racing ahead of a simulated- or real-latency op delivery. The default
 *   contract (omitted or `false`) transforms `author`'s cached selection
 *   through `delta` with `isOwnOperation=true` exactly like any other
 *   cached peer, on the assumption that the cache reflects `author`'s
 *   selection *before* this delta. When that assumption doesn't hold —
 *   because presence already raced ahead and the cached value is `author`'s
 *   position *after* this same delta — transforming it again would shift it
 *   a second time. Set `true` in that case: `author`'s cached selection (if
 *   any) is left untouched, while every *other* cached peer is still
 *   transformed through `delta` as usual. Has no effect when `author` is
 *   omitted, since no cached entry is then identified as the author's.
 */

/**
 * Structural subset of Quill's instance API this adapter depends on. Any
 * object exposing these four methods (real Quill, or a test double) works.
 * @typedef {Object} QuillLikeEditor
 * @property {(event: string, handler: (...args: any[]) => void) => void} on
 * @property {(event: string, handler: (...args: any[]) => void) => void} off
 * @property {(delta: unknown, source: string) => unknown} updateContents
 * @property {(delta: unknown, source?: string) => unknown} setContents
 */

/**
 * Pure selection-transform callback. This is **not** the generated
 * `rich_text.transform_selection` FFI export itself — that Gleam function
 * has signature `transform_selection(delta, selection, is_own_op) ->
 * Result(Selection, Error)`, a different argument order and a wrapped
 * result. Callers must supply a thin integration wrapper around it that:
 *
 *   1. Reorders arguments to `(selection, delta, isOwnOperation)`, calling
 *      the generated function as
 *      `transform_selection(delta, selection, isOwnOperation)`.
 *   2. Unwraps the returned `Result(Selection, Error)`, surfacing or
 *      falling back explicitly on `Error` (e.g. log and return the
 *      untransformed `selection`, or rethrow) — never pass the `Result`
 *      wrapper itself through as if it were a `RichTextSelection`.
 *
 * Must not mutate `selection` or `delta`.
 *
 * @callback TransformSelection
 * @param {RichTextSelection} selection
 * @param {unknown} delta
 * @param {boolean} isOwnOperation
 * @returns {RichTextSelection}
 */

/**
 * @typedef {Object} RichTextAdapterConfig
 * @property {QuillLikeEditor} editor
 * @property {(delta: unknown) => void} submitChange - Forward a
 *   user-originated delta to Watershed (e.g. a kernel's `change`/`submit`).
 * @property {(selection: RichTextSelection|null) => void} onLocalSelection -
 *   Publish the local user's normalized selection (e.g. into presence).
 * @property {(peers: ReadonlyArray<PeerSelectionEntry>) => void} onPeerSelections -
 *   Render the current peer-selection roster. Called with an immutable
 *   snapshot whenever the cache changes.
 * @property {TransformSelection} transformSelection
 * @property {Iterable<PeerSelectionEntry>} [initialPeers] - Optional seed
 *   roster (e.g. from an initial presence snapshot).
 */

/**
 * @typedef {Object} RichTextAdapter
 * @property {(event: RichTextChangeEvent) => void} applyChange
 * @property {(peers: Iterable<PeerSelectionEntry>) => void} replacePeerSelections
 * @property {(documentDelta: unknown) => void} loadDocument
 * @property {() => void} destroy
 * @property {() => ReadonlyArray<PeerSelectionEntry>} getPeerSelections
 */

const USER_SOURCE = "user";
const API_SOURCE = "api";
// Full-document load/reset (initial load or reconnect) is not an incremental
// edit relative to current content, so it must never be treated as an
// undoable delta. "silent" keeps Quill's History module from recording or
// transforming it, unlike the "api" source used for incremental remote ops.
const SILENT_SOURCE = "silent";

/**
 * Canonicalize a peer/author id for cache keys and identity comparisons, so
 * that numeric and string representations of the same id (e.g. `1` and
 * `"1"`) can never silently disagree. The original, non-canonicalized `id`
 * is preserved on cached entries for display.
 * @param {string|number} id
 * @returns {string}
 */
function canonicalId(id) {
  return typeof id === "number" ? String(id) : id;
}

/** @param {RichTextSelection|null|undefined} selection */
function cloneSelection(selection) {
  if (selection == null) return null;
  return { index: selection.index, length: selection.length };
}

/** @param {PeerSelectionEntry} entry */
function clonePeerEntry(entry) {
  return { ...entry, selection: cloneSelection(entry.selection) };
}

/**
 * @param {RichTextAdapterConfig} config
 * @returns {RichTextAdapter}
 */
export function createRichTextAdapter(config) {
  if (!config || typeof config !== "object") {
    throw new TypeError("createRichTextAdapter requires a config object");
  }
  const {
    editor,
    submitChange,
    onLocalSelection,
    onPeerSelections,
    transformSelection,
    initialPeers,
  } = config;
  for (const [key, value] of [
    ["editor", editor],
    ["submitChange", submitChange],
    ["onLocalSelection", onLocalSelection],
    ["onPeerSelections", onPeerSelections],
    ["transformSelection", transformSelection],
  ]) {
    if (value == null) {
      throw new TypeError(`createRichTextAdapter requires config.${key}`);
    }
  }

  /** @type {Map<string, PeerSelectionEntry>} keyed by canonicalId(entry.id) */
  const peers = new Map();
  if (initialPeers) {
    for (const entry of initialPeers) {
      peers.set(canonicalId(entry.id), clonePeerEntry(entry));
    }
  }

  let destroyed = false;

  function snapshotPeers() {
    return Array.from(peers.values(), clonePeerEntry);
  }

  function emitPeers() {
    onPeerSelections(snapshotPeers());
  }

  /**
   * Transform every cached peer selection through `delta`. `ownAuthorId`
   * identifies the peer whose own operation this is (isOwnOperation=true
   * for that one peer, false for the rest); pass `undefined` when the
   * operation isn't attributable to any cached peer, so every entry is
   * transformed as a remote (isOwnOperation=false) change. Compared against
   * cached peer ids via `canonicalId`, so numeric and string forms of the
   * same id (e.g. `1` and `"1"`) match.
   *
   * `skipAuthorTransform` — see `RichTextChangeEvent.authorSelectionAlreadyApplied`
   * — leaves `ownAuthorId`'s cached entry untouched instead of transforming
   * it, when the caller's own presence path has already delivered that
   * peer's post-edit selection ahead of `delta`. Every other cached peer is
   * still transformed as usual.
   * @param {unknown} delta
   * @param {string|number|undefined} ownAuthorId
   * @param {boolean} [skipAuthorTransform]
   */
  function transformPeersThroughDelta(delta, ownAuthorId, skipAuthorTransform) {
    if (peers.size === 0) return;
    const ownKey = ownAuthorId !== undefined ? canonicalId(ownAuthorId) : undefined;
    let touched = false;
    for (const [id, entry] of peers) {
      if (entry.selection == null) continue;
      const isOwnOperation = ownKey !== undefined && id === ownKey;
      if (skipAuthorTransform && isOwnOperation) {
        // Already the author's post-edit position (delivered out-of-band,
        // ahead of this delta) — transforming it again would double-shift
        // it, so leave this one cached entry as-is.
        continue;
      }
      const transformed = transformSelection(
        cloneSelection(entry.selection),
        delta,
        isOwnOperation,
      );
      peers.set(id, { ...entry, selection: cloneSelection(transformed) });
      touched = true;
    }
    if (touched) emitPeers();
  }

  /** @param {{index: number, length: number}|null|undefined} range */
  function normalizeSelection(range) {
    if (range == null) return null;
    return { index: range.index, length: range.length };
  }

  /**
   * @param {unknown} delta
   * @param {unknown} _oldDelta
   * @param {string} source
   */
  function handleTextChange(delta, _oldDelta, source) {
    if (destroyed) return;
    // Only genuine user edits are submitted; anything the adapter itself
    // applied (source "api" from `applyChange`, or "silent" from
    // `loadDocument`) must never be resubmitted.
    if (source !== USER_SOURCE) return;
    submitChange(delta);
    // The local user's own edit — every cached peer is necessarily remote
    // relative to it.
    transformPeersThroughDelta(delta, undefined);
  }

  /**
   * @param {{index: number, length: number}|null} range
   * @param {{index: number, length: number}|null} _oldRange
   * @param {string} _source
   */
  function handleSelectionChange(range, _oldRange, _source) {
    if (destroyed) return;
    onLocalSelection(normalizeSelection(range));
  }

  editor.on("text-change", handleTextChange);
  editor.on("selection-change", handleSelectionChange);

  return {
    /** @param {RichTextChangeEvent} event */
    applyChange(event) {
      if (destroyed) return;
      const { delta, local, author, authorSelectionAlreadyApplied } = event;
      if (local) {
        // The editor already rendered this optimistically when the user
        // typed it (see handleTextChange); applying it again — or
        // re-transforming peers through it a second time — would be wrong.
        return;
      }
      editor.updateContents(delta, API_SOURCE);
      transformPeersThroughDelta(delta, author, authorSelectionAlreadyApplied === true);
    },

    /** @param {Iterable<PeerSelectionEntry>} nextPeers */
    replacePeerSelections(nextPeers) {
      if (destroyed) return;
      peers.clear();
      for (const entry of nextPeers) {
        if (entry == null || entry.id == null) {
          throw new TypeError("peer selection entry requires an id");
        }
        peers.set(canonicalId(entry.id), clonePeerEntry(entry));
      }
      emitPeers();
    },

    /** @param {unknown} documentDelta */
    loadDocument(documentDelta) {
      if (destroyed) return;
      editor.setContents(documentDelta, SILENT_SOURCE);
    },

    destroy() {
      if (destroyed) return;
      destroyed = true;
      editor.off("text-change", handleTextChange);
      editor.off("selection-change", handleSelectionChange);
    },

    getPeerSelections() {
      return snapshotPeers();
    },
  };
}
