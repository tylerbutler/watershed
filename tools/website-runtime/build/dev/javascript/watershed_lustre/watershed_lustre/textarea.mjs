/// <reference types="./textarea.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dynamic from "../../gleam_stdlib/gleam/dynamic.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $float from "../../gleam_stdlib/gleam/float.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $attribute from "../../lustre/lustre/attribute.mjs";
import * as $effect from "../../lustre/lustre/effect.mjs";
import * as $element from "../../lustre/lustre/element.mjs";
import * as $html from "../../lustre/lustre/element/html.mjs";
import * as $event from "../../lustre/lustre/event.mjs";
import * as $watershed from "../../watershed/watershed.mjs";
import * as $crdt_js from "../../watershed/watershed/crdt_js.mjs";
import * as $schema from "../../watershed/watershed/schema.mjs";
import * as $text_kernel from "../../watershed/watershed/text_kernel.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  CustomType as $CustomType,
  isEqual,
} from "../gleam.mjs";
import * as $watershed_lustre from "../watershed_lustre.mjs";
import * as $crdt from "../watershed_lustre/crdt.mjs";
import * as $grapheme_diff from "../watershed_lustre/grapheme_diff.mjs";
import * as $grapheme_offset from "../watershed_lustre/grapheme_offset.mjs";
import { identity as dynamic_to_dom_root, restore_selection, measure_cursors } from "./textarea_ffi.mjs";

class Backend extends $CustomType {
  constructor(snapshot, insert, delete_range, replace_range, anchor_at, resolve_anchor) {
    super();
    this.snapshot = snapshot;
    this.insert = insert;
    this.delete_range = delete_range;
    this.replace_range = replace_range;
    this.anchor_at = anchor_at;
    this.resolve_anchor = resolve_anchor;
  }
}

class Model extends $CustomType {
  constructor(channel, backend, instance, value, length, selection, composing, committed, error, subscription, peers) {
    super();
    this.channel = channel;
    this.backend = backend;
    this.instance = instance;
    this.value = value;
    this.length = length;
    this.selection = selection;
    this.composing = composing;
    this.committed = committed;
    this.error = error;
    this.subscription = subscription;
    this.peers = peers;
  }
}

class Peer extends $CustomType {
  constructor(id, label, colour, cursor, range, caret, bands) {
    super();
    this.id = id;
    this.label = label;
    this.colour = colour;
    this.cursor = cursor;
    this.range = range;
    this.caret = caret;
    this.bands = bands;
  }
}

class Rect extends $CustomType {
  constructor(x, y, width, height) {
    super();
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
  }
}

class Cursor extends $CustomType {
  constructor(start, end) {
    super();
    this.start = start;
    this.end = end;
  }
}

class Composition extends $CustomType {
  constructor(frozen, region, span) {
    super();
    this.frozen = frozen;
    this.region = region;
    this.span = span;
  }
}

class Selection extends $CustomType {
  constructor(start, end, range, raw) {
    super();
    this.start = start;
    this.end = end;
    this.range = range;
    this.raw = raw;
  }
}

/**
 * The channel changed, from a local edit or from a remote one. The message
 * carries the string after that edit. The model reads the channel again all
 * the same, so the render always shows the committed optimistic state, and
 * not the payload of an event.
 * 
 * @ignore
 */
class KernelEvent extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

/**
 * The cancellable subscription of a sequenced text binding.
 * 
 * @ignore
 */
class ClassicSubscribed extends $CustomType {
  constructor(instance, subscription) {
    super();
    this.instance = instance;
    this.subscription = subscription;
  }
}

/**
 * The subscription handle of the p2p binding. The component has no teardown
 * path, so it ignores this message on purpose.
 * 
 * @ignore
 */
class P2pSubscribed extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

/**
 * The user typed. The message carries the whole new value of the textarea,
 * and the caret position after that input, in UTF-16 code units.
 * 
 * @ignore
 */
class UserInput extends $CustomType {
  constructor(value, selection_start, selection_end) {
    super();
    this.value = value;
    this.selection_start = selection_start;
    this.selection_end = selection_end;
  }
}

/**
 * The user moved the caret, or changed the selection, and made no edit.
 * 
 * @ignore
 */
class UserSelect extends $CustomType {
  constructor(selection_start, selection_end) {
    super();
    this.selection_start = selection_start;
    this.selection_end = selection_end;
  }
}

/**
 * An IME session opened. The message carries the value of the element and
 * the caret position, as they were before the browser inserted any
 * provisional text.
 * 
 * @ignore
 */
class CompositionStarted extends $CustomType {
  constructor(value, selection_start, selection_end) {
    super();
    this.value = value;
    this.selection_start = selection_start;
    this.selection_end = selection_end;
  }
}

/**
 * An IME session committed. The message carries the final value of the
 * element and the caret position.
 * 
 * @ignore
 */
class CompositionEnded extends $CustomType {
  constructor(value, selection_start, selection_end) {
    super();
    this.value = value;
    this.selection_start = selection_start;
    this.selection_end = selection_end;
  }
}

/**
 * The geometry of the peer cursors, which the component measured on the
 * mirror, between the vdom write and the paint of the browser. The message
 * carries the JSON response of the FFI.
 * 
 * @ignore
 */
class Measured extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

/**
 * The approximate height of a name tag. The component uses it only to select
 * the side of the caret that the tag attaches to, so an approximate value is
 * sufficient.
 * 
 * @ignore
 */
const label_height = 18.0;

/**
 * The attribute that the measurer uses to find the mirror of this instance.
 * 
 * @ignore
 */
const mirror_attribute = "data-watershed-mirror";

/**
 * The value that a caret decoder gives when the element reported no selection
 * at all. This value differs from `0`, which is a real caret at the start of
 * the document.
 * 
 * @ignore
 */
const unknown_caret = -1;

/**
 * The attribute that the caret restorer uses to find the element. The
 * component writes it after the attributes of the caller, so a caller cannot
 * replace it.
 * 
 * @ignore
 */
const instance_attribute = "data-watershed-textarea";

/**
 * Whether the handler of this message can write to the bound text channel.
 *
 * A parent can use this function to apply a read-only mode. It then keeps the
 * remote channel events, the selection updates, and the cursor
 * measurements.
 */
export function mutates_document(msg) {
  if (msg instanceof KernelEvent) {
    return false;
  } else if (msg instanceof ClassicSubscribed) {
    return false;
  } else if (msg instanceof P2pSubscribed) {
    return false;
  } else if (msg instanceof UserInput) {
    return true;
  } else if (msg instanceof UserSelect) {
    return false;
  } else if (msg instanceof CompositionStarted) {
    return true;
  } else if (msg instanceof CompositionEnded) {
    return true;
  } else {
    return false;
  }
}

function sequenced_backend() {
  return new Backend(
    (channel) => {
      return new Ok(
        [$watershed.text_value(channel), $watershed.text_length(channel)],
      );
    },
    (channel, index, value) => {
      return $watershed.text_insert(channel, index, value);
    },
    (channel, start, end) => {
      return $watershed.text_delete_range(channel, start, end);
    },
    (channel, start, end, value) => {
      return $watershed.text_replace_range(channel, start, end, value);
    },
    (channel, index, bias) => {
      let _pipe = $watershed.text_anchor_at(channel, index, bias);
      return $result.replace_error(_pipe, undefined);
    },
    (channel, anchor) => {
      let _pipe = $watershed.text_resolve_anchor(channel, anchor);
      return $result.replace_error(_pipe, undefined);
    },
  );
}

/**
 * Read the optimistic state of the channel into the model again.
 * 
 * @ignore
 */
function snapshot(model) {
  let $ = model.backend.snapshot(model.channel);
  if ($ instanceof Ok) {
    let value$1 = $[0][0];
    let length$1 = $[0][1];
    return new Model(
      model.channel,
      model.backend,
      model.instance,
      value$1,
      length$1,
      model.selection,
      model.composing,
      model.committed,
      model.error,
      model.subscription,
      model.peers,
    );
  } else {
    return model;
  }
}

/**
 * A key that is unique to this instance of the component. An application that
 * renders several instances thus restores the caret of each one into its own
 * element.
 * 
 * @ignore
 */
function new_instance() {
  return (("wst-" + $int.to_string($int.random(1_000_000_000))) + "-") + $int.to_string(
    $int.random(1_000_000_000),
  );
}

function init_with(channel, backend, subscribe) {
  let instance = new_instance();
  let model = snapshot(
    new Model(
      channel,
      backend,
      instance,
      "",
      0,
      Option$None$const,
      Option$None$const,
      Option$None$const,
      Option$None$const,
      Option$None$const,
      $List$Empty$const,
    ),
  );
  return [model, subscribe(instance)];
}

/**
 * Bind a resolved text channel. The function subscribes to that channel and
 * takes the first snapshot. A tab that joins an existing document thus renders
 * the text immediately, and it does not wait for the first edit.
 *
 * The argument is a resolved channel, and not an `Option` value. Construct the
 * component in the `ensure_text` callback. The model thus never holds an empty
 * channel, and the view never renders a disabled element. Render any
 * placeholder that you want before that moment.
 */
export function init(channel) {
  return init_with(
    channel,
    sequenced_backend(),
    (instance) => {
      return $watershed_lustre.subscribe_text_cancellable(
        channel,
        (var0) => { return new KernelEvent(var0); },
        (subscription) => {
          return new ClassicSubscribed(instance, subscription);
        },
      );
    },
  );
}

function crdt_resolve_anchor(channel, anchor) {
  let _pipe = $crdt_js.text_resolve_anchor(channel, anchor);
  return $result.replace_error(_pipe, undefined);
}

function crdt_anchor_at(channel, index, bias) {
  let _pipe = $crdt_js.text_anchor_at(channel, index, bias);
  return $result.replace_error(_pipe, undefined);
}

function crdt_snapshot(channel) {
  let $ = $crdt_js.text_value(channel);
  let $1 = $crdt_js.text_length(channel);
  if ($ instanceof Ok) {
    if ($1 instanceof Ok) {
      let value$1 = $[0];
      let length$1 = $1[0];
      return new Ok([value$1, length$1]);
    } else {
      let reason = $1[0];
      return new Error($crdt_js.describe_error(reason));
    }
  } else if ($1 instanceof Ok) {
    let reason = $[0];
    return new Error($crdt_js.describe_error(reason));
  } else {
    let reason = $[0];
    return new Error($crdt_js.describe_error(reason));
  }
}

function crdt_backend() {
  return new Backend(
    crdt_snapshot,
    (channel, index, value) => {
      let $ = $crdt_js.text_insert(channel, index, value);
      if ($ instanceof Ok) {
        return $;
      } else {
        let reason = $[0];
        return new Error($crdt_js.describe_error(reason));
      }
    },
    (channel, start, end) => {
      let $ = $crdt_js.text_delete_range(channel, start, end);
      if ($ instanceof Ok) {
        return $;
      } else {
        let reason = $[0];
        return new Error($crdt_js.describe_error(reason));
      }
    },
    (channel, start, end, value) => {
      let $ = $crdt_js.text_replace_range(channel, start, end, value);
      if ($ instanceof Ok) {
        return $;
      } else {
        let reason = $[0];
        return new Error($crdt_js.describe_error(reason));
      }
    },
    crdt_anchor_at,
    crdt_resolve_anchor,
  );
}

/**
 * Bind a resolved peer-to-peer text handle. The component logic is the same as
 * in [`init`](#init), and this function subscribes through
 * `watershed_lustre/crdt`.
 */
export function init_crdt(channel) {
  return init_with(
    channel,
    crdt_backend(),
    (_) => {
      return $crdt.subscribe_text(
        channel,
        (var0) => { return new P2pSubscribed(var0); },
        (var0) => { return new KernelEvent(var0); },
      );
    },
  );
}

/**
 * Ask the mirror for the position of the range of each peer. The function runs
 * in the same `before_paint` window as the caret, after the vdom writes the
 * text of the mirror and before the browser paints anything. A cursor thus
 * never appears at a stale position.
 *
 * The reply arrives as a message, and this function does not apply it. That
 * design keeps the loop finite: `Measured` writes geometry and nothing else, so
 * it cannot request another measurement.
 * 
 * @ignore
 */
function measure(model) {
  let drawable = $list.filter_map(
    model.peers,
    (peer) => {
      let $ = peer.range;
      if ($ instanceof Some) {
        let start = $[0][0];
        let end = $[0][1];
        return new Ok(
          $json.object(
            toList([
              ["id", $json.string(peer.id)],
              ["start", $json.int(start)],
              ["end", $json.int(end)],
            ]),
          ),
        );
      } else {
        return new Error(undefined);
      }
    },
  );
  if (drawable instanceof $Empty) {
    return $effect.none();
  } else {
    let request = $json.to_string($json.preprocessed_array(drawable));
    let instance = model.instance;
    return $effect.before_paint(
      (dispatch, root) => {
        return dispatch(
          new Measured(
            measure_cursors(dynamic_to_dom_root(root), instance, request),
          ),
        );
      },
    );
  }
}

/**
 * Write the tracked selection back into the element, in the window between the
 * vdom write of its value and the paint of the browser.
 * 
 * @ignore
 */
function restore(model) {
  let $ = model.selection;
  if ($ instanceof Some) {
    let selection$1 = $[0];
    let $1 = selection$1.raw;
    let start = $1[0];
    let end = $1[1];
    let instance = model.instance;
    return $effect.before_paint(
      (_, root) => {
        return restore_selection(
          dynamic_to_dom_root(root),
          instance,
          start,
          end,
        );
      },
    );
  } else {
    return $effect.none();
  }
}

/**
 * Resolve the anchors of every peer against this replica, and convert the
 * result to the code units that the DOM measures in. The function runs when the
 * peers change, and when the text moves.
 * 
 * @ignore
 */
function locate(model) {
  let peers = $list.map(
    model.peers,
    (peer) => {
      let _block;
      let $ = model.backend.resolve_anchor(model.channel, peer.cursor.start);
      let $1 = model.backend.resolve_anchor(model.channel, peer.cursor.end);
      if ($ instanceof Ok) {
        if ($1 instanceof Ok) {
          let start = $[0];
          let end = $1[0];
          _block = new Some(
            [
              $grapheme_offset.to_utf16(model.value, $int.min(start, end)),
              $grapheme_offset.to_utf16(model.value, $int.max(start, end)),
            ],
          );
        } else {
          _block = Option$None$const;
        }
      } else if ($1 instanceof Ok) {
        _block = Option$None$const;
      } else {
        _block = Option$None$const;
      }
      let range = _block;
      return new Peer(
        peer.id,
        peer.label,
        peer.colour,
        peer.cursor,
        range,
        peer.caret,
        peer.bands,
      );
    },
  );
  return new Model(
    model.channel,
    model.backend,
    model.instance,
    model.value,
    model.length,
    model.selection,
    model.composing,
    model.committed,
    model.error,
    model.subscription,
    peers,
  );
}

/**
 * Bind a grapheme range to the content that it covers.
 *
 * The biases follow the association convention at the top of this module, and
 * this function is the only place that selects them. A collapsed position
 * attaches to the grapheme before it, at both ends, so a remote insert there
 * leaves that position before the inserted text. A range holds its content, so
 * an insert at either edge falls outside it, and an edit inside it makes the
 * range larger or smaller. The selection of the user and the region that an IME
 * composes over need the same rule, for the same reason.
 *
 * The result is `Error(Nil)` for a position that the CRDT cannot name.
 * 
 * @ignore
 */
function anchors(model, start, end) {
  let _block;
  let $ = start === end;
  if ($) {
    _block = $watershed.bias_after;
  } else {
    _block = $watershed.bias_before;
  }
  let head_bias = _block;
  let $1 = model.backend.anchor_at(model.channel, start, head_bias);
  let $2 = model.backend.anchor_at(model.channel, end, $watershed.bias_after);
  if ($1 instanceof Ok) {
    if ($2 instanceof Ok) {
      let head = $1[0];
      let tail = $2[0];
      return new Ok([head, tail]);
    } else {
      return new Error(undefined);
    }
  } else if ($2 instanceof Ok) {
    return new Error(undefined);
  } else {
    return new Error(undefined);
  }
}

/**
 * Pin new anchors at a grapheme range, clamped into the current text, and
 * record that range in both coordinate systems.
 * 
 * @ignore
 */
function pin(model, start, end) {
  let start$1 = $int.clamp(start, 0, model.length);
  let end$1 = $int.clamp(end, 0, model.length);
  let $ = anchors(model, start$1, end$1);
  if ($ instanceof Ok) {
    let head = $[0][0];
    let tail = $[0][1];
    return new Model(
      model.channel,
      model.backend,
      model.instance,
      model.value,
      model.length,
      new Some(
        new Selection(
          head,
          tail,
          [start$1, end$1],
          [
            $grapheme_offset.to_utf16(model.value, start$1),
            $grapheme_offset.to_utf16(model.value, end$1),
          ],
        ),
      ),
      model.composing,
      model.committed,
      model.error,
      model.subscription,
      model.peers,
    );
  } else {
    return new Model(
      model.channel,
      model.backend,
      model.instance,
      model.value,
      model.length,
      Option$None$const,
      model.composing,
      model.committed,
      model.error,
      model.subscription,
      model.peers,
    );
  }
}

/**
 * Resolve the held anchors against the current text of the channel, and pin
 * them again at their new positions.
 * 
 * @ignore
 */
function resolve(model) {
  let $ = model.selection;
  if ($ instanceof Some) {
    let selection$1 = $[0];
    let $1 = model.backend.resolve_anchor(model.channel, selection$1.start);
    let $2 = model.backend.resolve_anchor(model.channel, selection$1.end);
    if ($1 instanceof Ok) {
      if ($2 instanceof Ok) {
        let start = $1[0];
        let end = $2[0];
        return pin(model, start, end);
      } else {
        let index = $1[0];
        return pin(model, index, index);
      }
    } else if ($2 instanceof Ok) {
      let index = $2[0];
      return pin(model, index, index);
    } else {
      return new Model(
        model.channel,
        model.backend,
        model.instance,
        model.value,
        model.length,
        Option$None$const,
        model.composing,
        model.committed,
        model.error,
        model.subscription,
        model.peers,
      );
    }
  } else {
    return model;
  }
}

function verb(edit) {
  if (edit instanceof $grapheme_diff.NoChange) {
    return "noop";
  } else if (edit instanceof $grapheme_diff.Insert) {
    return "insert";
  } else if (edit instanceof $grapheme_diff.Delete) {
    return "delete";
  } else {
    return "replace";
  }
}

/**
 * Put the result of an edit into the model. The function clears the message on
 * a success, and it keeps the message of the runtime on a failure.
 * 
 * @ignore
 */
function record(model, result, edit) {
  if (result instanceof Ok) {
    return new Model(
      model.channel,
      model.backend,
      model.instance,
      model.value,
      model.length,
      model.selection,
      model.composing,
      model.committed,
      Option$None$const,
      model.subscription,
      model.peers,
    );
  } else {
    let reason = result[0];
    return new Model(
      model.channel,
      model.backend,
      model.instance,
      model.value,
      model.length,
      model.selection,
      model.composing,
      model.committed,
      new Some((verb(edit) + " failed: ") + reason),
      model.subscription,
      model.peers,
    );
  }
}

/**
 * Run a computed `Edit` value against the channel, as one minimal operation.
 * 
 * @ignore
 */
function apply(model, edit) {
  if (edit instanceof $grapheme_diff.NoChange) {
    return new Ok(undefined);
  } else if (edit instanceof $grapheme_diff.Insert) {
    let index = edit.index;
    let value$1 = edit.value;
    return model.backend.insert(model.channel, index, value$1);
  } else if (edit instanceof $grapheme_diff.Delete) {
    let start = edit.start;
    let end = edit.end;
    return model.backend.delete_range(model.channel, start, end);
  } else {
    let start = edit.start;
    let end = edit.end;
    let value$1 = edit.value;
    return model.backend.replace_range(model.channel, start, end, value$1);
  }
}

/**
 * The one operation that applies everything that the user composed.
 *
 * The two halves of the session answer separate questions, and this function
 * keeps them separate. The final value of the element says *what the user
 * typed*. The resolved span says *where that text goes and what it replaces*.
 *
 * The function recovers the typed text against a known region, and it does not
 * diff for that text. The extent of the region thus comes from the anchors. A
 * diff would derive an extent again in the stale coordinates of the frozen
 * string, and a caller can re-address such an extent only when the whole
 * region moved as one block.
 * 
 * @ignore
 */
function commit(composition, value, start, end, shift) {
  let $ = value === composition.frozen;
  if ($) {
    return $grapheme_diff.Edit$NoChange$const;
  } else {
    let $1 = $grapheme_diff.replacement(
      composition.frozen,
      value,
      composition.region,
    );
    if ($1 instanceof Ok) {
      let composed = $1[0];
      return $grapheme_diff.splice(start, end, composed);
    } else {
      let _pipe = $grapheme_diff.diff(composition.frozen, value);
      return $grapheme_diff.shift(_pipe, shift);
    }
  }
}

/**
 * The current position of the composed-over region, in graphemes.
 *
 * The session opened over a region of a string, and the peers can have edited
 * that string several times after that. The function thus reads both ends of
 * the region from the anchors. It does not assume that the two ends moved
 * together. That is the purpose of an anchored span: an insert inside the
 * region moves its tail and not its head, and one offset cannot report that.
 *
 * Every fallback keeps the width of the region, because the user chose that
 * width. Only the position is in question. If the function can name neither
 * end, the region stays at the position where the user typed it. That result
 * is correct whenever no peer edited the text before it, and it converges in
 * every case.
 * 
 * @ignore
 */
function site(model, composition) {
  let $ = composition.region;
  let origin_start = $[0];
  let origin_end = $[1];
  let width = origin_end - origin_start;
  let $1 = composition.span;
  if ($1 instanceof Ok) {
    let head = $1[0][0];
    let tail = $1[0][1];
    let $2 = model.backend.resolve_anchor(model.channel, head);
    let $3 = model.backend.resolve_anchor(model.channel, tail);
    if ($2 instanceof Ok) {
      if ($3 instanceof Ok) {
        let start = $2[0];
        let end = $3[0];
        return [start, $int.max(start, end)];
      } else {
        let start = $2[0];
        return [start, start + width];
      }
    } else if ($3 instanceof Ok) {
      let end = $3[0];
      return [$int.max(0, end - width), end];
    } else {
      return composition.region;
    }
  } else {
    return composition.region;
  }
}

/**
 * A UTF-16 offset that an element reported, as a grapheme index into the
 * current document. `text` is the string that those offsets index into, and it
 * is not always the string that the model holds.
 * 
 * @ignore
 */
function reported(model, text, offset) {
  return $int.clamp(
    $grapheme_offset.from_utf16(text, $int.max(offset, 0)),
    0,
    model.length,
  );
}

/**
 * Anchor again, from the offsets that an element reported, read against
 * `text`. That string is the one that those offsets index into, and it is not
 * always the string that the model holds.
 * 
 * @ignore
 */
function anchor(model, text, selection_start, selection_end) {
  let $ = (selection_start < 0) || (selection_end < 0);
  if ($) {
    return model;
  } else {
    let $1 = model.selection;
    if ($1 instanceof Some) {
      let selection$1 = $1[0];
      if (isEqual(selection$1.raw, [selection_start, selection_end])) {
        return model;
      } else {
        return pin(
          model,
          $grapheme_offset.from_utf16(text, selection_start),
          $grapheme_offset.from_utf16(text, selection_end),
        );
      }
    } else {
      return pin(
        model,
        $grapheme_offset.from_utf16(text, selection_start),
        $grapheme_offset.from_utf16(text, selection_end),
      );
    }
  }
}

/**
 * The current optimistic string. If a read of the backend failed, the result is
 * the last correct snapshot.
 * 
 * @ignore
 */
function current(model) {
  let $ = model.backend.snapshot(model.channel);
  if ($ instanceof Ok) {
    let value$1 = $[0][0];
    return value$1;
  } else {
    return model.value;
  }
}

function rect_decoder() {
  return $decode.field(
    "x",
    $decode.float,
    (x) => {
      return $decode.field(
        "y",
        $decode.float,
        (y) => {
          return $decode.field(
            "width",
            $decode.float,
            (width) => {
              return $decode.field(
                "height",
                $decode.float,
                (height) => {
                  return $decode.success(new Rect(x, y, width, height));
                },
              );
            },
          );
        },
      );
    },
  );
}

function measurement_decoder() {
  return $decode.field(
    "id",
    $decode.string,
    (id) => {
      return $decode.field(
        "caret",
        $decode.optional(rect_decoder()),
        (caret) => {
          return $decode.field(
            "bands",
            $decode.list(rect_decoder()),
            (bands) => { return $decode.success([id, caret, bands]); },
          );
        },
      );
    },
  );
}

/**
 * Put the measured geometry back onto the peers that it belongs to. The
 * function matches by id, and not by position, because the roster can change
 * between the request and the answer.
 * 
 * @ignore
 */
function place(model, response) {
  let $ = $json.parse(response, $decode.list(measurement_decoder()));
  if ($ instanceof Ok) {
    let measurements = $[0];
    let peers = $list.map(
      model.peers,
      (peer) => {
        let $1 = $list.find(
          measurements,
          (measurement) => { return measurement[0] === peer.id; },
        );
        if ($1 instanceof Ok) {
          let caret$1 = $1[0][1];
          let bands = $1[0][2];
          return new Peer(
            peer.id,
            peer.label,
            peer.colour,
            peer.cursor,
            peer.range,
            caret$1,
            bands,
          );
        } else {
          return new Peer(
            peer.id,
            peer.label,
            peer.colour,
            peer.cursor,
            peer.range,
            Option$None$const,
            $List$Empty$const,
          );
        }
      },
    );
    return new Model(
      model.channel,
      model.backend,
      model.instance,
      model.value,
      model.length,
      model.selection,
      model.composing,
      model.committed,
      model.error,
      model.subscription,
      peers,
    );
  } else {
    return model;
  }
}

/**
 * Put a new snapshot into the view. The function restores the caret only when
 * the text moved below the element.
 * 
 * @ignore
 */
function settle(model, rendered) {
  let $ = model.value === rendered;
  if ($) {
    return [model, $effect.none()];
  } else {
    let model$1 = locate(resolve(model));
    return [
      model$1,
      $effect.batch(toList([restore(model$1), measure(model$1)])),
    ];
  }
}

export function update(loop$model, loop$msg) {
  while (true) {
    let model = loop$model;
    let msg = loop$msg;
    if (msg instanceof KernelEvent) {
      let rendered = model.value;
      let model$1 = snapshot(model);
      let $ = model$1.composing;
      if ($ instanceof Some) {
        return [resolve(model$1), $effect.none()];
      } else {
        return settle(model$1, rendered);
      }
    } else if (msg instanceof ClassicSubscribed) {
      let instance = msg.instance;
      let subscription = msg.subscription;
      let $ = instance === model.instance;
      if ($) {
        return [
          new Model(
            model.channel,
            model.backend,
            model.instance,
            model.value,
            model.length,
            model.selection,
            model.composing,
            model.committed,
            model.error,
            new Some(subscription),
            model.peers,
          ),
          $effect.none(),
        ];
      } else {
        $watershed.unsubscribe(subscription);
        return [model, $effect.none()];
      }
    } else if (msg instanceof P2pSubscribed) {
      return [model, $effect.none()];
    } else if (msg instanceof UserInput) {
      let value$1 = msg.value;
      let selection_start = msg.selection_start;
      let selection_end = msg.selection_end;
      let $ = model.composing;
      let $1 = model.committed;
      if ($ instanceof Some) {
        if ($1 instanceof Some) {
          return [model, $effect.none()];
        } else {
          return [model, $effect.none()];
        }
      } else if ($1 instanceof Some) {
        let committed = $1[0];
        if (committed === value$1) {
          return [
            new Model(
              model.channel,
              model.backend,
              model.instance,
              model.value,
              model.length,
              model.selection,
              model.composing,
              Option$None$const,
              model.error,
              model.subscription,
              model.peers,
            ),
            $effect.none(),
          ];
        } else {
          let model$1 = new Model(
            model.channel,
            model.backend,
            model.instance,
            model.value,
            model.length,
            model.selection,
            model.composing,
            Option$None$const,
            model.error,
            model.subscription,
            model.peers,
          );
          let edit = $grapheme_diff.diff(current(model$1), value$1);
          let result = apply(model$1, edit);
          let model$2 = record(snapshot(model$1), result, edit);
          let model$3 = locate(
            anchor(model$2, value$1, selection_start, selection_end),
          );
          let $2 = model$3.value === value$1;
          if ($2) {
            return [model$3, measure(model$3)];
          } else {
            return [
              model$3,
              $effect.batch(toList([restore(model$3), measure(model$3)])),
            ];
          }
        }
      } else {
        let model$1 = new Model(
          model.channel,
          model.backend,
          model.instance,
          model.value,
          model.length,
          model.selection,
          model.composing,
          Option$None$const,
          model.error,
          model.subscription,
          model.peers,
        );
        let edit = $grapheme_diff.diff(current(model$1), value$1);
        let result = apply(model$1, edit);
        let model$2 = record(snapshot(model$1), result, edit);
        let model$3 = locate(
          anchor(model$2, value$1, selection_start, selection_end),
        );
        let $2 = model$3.value === value$1;
        if ($2) {
          return [model$3, measure(model$3)];
        } else {
          return [
            model$3,
            $effect.batch(toList([restore(model$3), measure(model$3)])),
          ];
        }
      }
    } else if (msg instanceof UserSelect) {
      let selection_start = msg.selection_start;
      let selection_end = msg.selection_end;
      let $ = model.composing;
      if ($ instanceof Some) {
        return [model, $effect.none()];
      } else {
        return [
          anchor(model, model.value, selection_start, selection_end),
          $effect.none(),
        ];
      }
    } else if (msg instanceof CompositionStarted) {
      let value$1 = msg.value;
      let selection_start = msg.selection_start;
      let selection_end = msg.selection_end;
      let head = reported(model, value$1, selection_start);
      let _block;
      let $ = selection_end < 0;
      if ($) {
        _block = head;
      } else {
        _block = reported(model, value$1, selection_end);
      }
      let tail = _block;
      let region = [$int.min(head, tail), $int.max(head, tail)];
      return [
        new Model(
          model.channel,
          model.backend,
          model.instance,
          model.value,
          model.length,
          model.selection,
          new Some(
            new Composition(
              value$1,
              region,
              anchors(model, region[0], region[1]),
            ),
          ),
          Option$None$const,
          model.error,
          model.subscription,
          model.peers,
        ),
        $effect.none(),
      ];
    } else if (msg instanceof CompositionEnded) {
      let value$1 = msg.value;
      let selection_start = msg.selection_start;
      let selection_end = msg.selection_end;
      let $ = model.composing;
      if ($ instanceof Some) {
        let composition = $[0];
        let $1 = site(model, composition);
        let start = $1[0];
        let end = $1[1];
        let shift = start - composition.region[0];
        let edit = commit(composition, value$1, start, end, shift);
        let result = apply(model, edit);
        let _block;
        let _pipe = new Model(
          model.channel,
          model.backend,
          model.instance,
          model.value,
          model.length,
          model.selection,
          Option$None$const,
          new Some(value$1),
          model.error,
          model.subscription,
          model.peers,
        );
        let _pipe$1 = snapshot(_pipe);
        _block = record(_pipe$1, result, edit);
        let model$1 = _block;
        let _block$1;
        let $2 = (selection_start < 0) || (selection_end < 0);
        if ($2) {
          _block$1 = resolve(model$1);
        } else {
          _block$1 = pin(
            model$1,
            $grapheme_offset.from_utf16(value$1, selection_start) + shift,
            $grapheme_offset.from_utf16(value$1, selection_end) + shift,
          );
        }
        let model$2 = _block$1;
        let model$3 = locate(model$2);
        return [
          model$3,
          $effect.batch(toList([restore(model$3), measure(model$3)])),
        ];
      } else {
        loop$model = model;
        loop$msg = new UserInput(value$1, selection_start, selection_end);
      }
    } else {
      let response = msg[0];
      return [place(model, response), $effect.none()];
    }
  }
}

/**
 * The bound element itself.
 * 
 * @ignore
 */
function field_view(model, bindings) {
  let $ = model.composing;
  if ($ instanceof Some) {
    let composition = $[0];
    return $element.element(
      "textarea",
      bindings,
      toList([$element.text(composition.frozen)]),
    );
  } else {
    return $html.textarea(bindings, model.value);
  }
}

function pixels(value) {
  return $float.to_string(value) + "px";
}

function peer_view(peer) {
  let bands = $list.map(
    peer.bands,
    (band) => {
      return $html.div(
        toList([
          $attribute.style("position", "absolute"),
          $attribute.style("left", pixels(band.x)),
          $attribute.style("top", pixels(band.y)),
          $attribute.style("width", pixels(band.width)),
          $attribute.style("height", pixels(band.height)),
          $attribute.style("background", peer.colour),
          $attribute.style("opacity", "0.25"),
          $attribute.style("border-radius", "0.125rem"),
        ]),
        $List$Empty$const,
      );
    },
  );
  let _block;
  let $ = peer.caret;
  if ($ instanceof Some) {
    let rect = $[0];
    _block = toList([
      $html.div(
        toList([
          $attribute.style("position", "absolute"),
          $attribute.style("left", pixels(rect.x)),
          $attribute.style("top", pixels(rect.y)),
          $attribute.style("width", "2px"),
          $attribute.style("height", pixels(rect.height)),
          $attribute.style("background", peer.colour),
        ]),
        toList([
          $html.span(
            toList([
              $attribute.style("position", "absolute"),
              (() => {
                let $1 = rect.y < label_height;
                if ($1) {
                  return $attribute.style("top", "100%");
                } else {
                  return $attribute.style("top", "-1.15em");
                }
              })(),
              $attribute.style("left", "-1px"),
              $attribute.style("padding", "0 0.25rem"),
              $attribute.style("border-radius", "0.25rem"),
              $attribute.style("background", peer.colour),
              $attribute.style("color", "white"),
              $attribute.style("font-size", "0.7rem"),
              $attribute.style("line-height", "1.5"),
              $attribute.style("white-space", "nowrap"),
            ]),
            toList([$html.text(peer.label)]),
          ),
        ]),
      ),
    ]);
  } else {
    _block = $List$Empty$const;
  }
  let caret$1 = _block;
  return $list.append(bands, caret$1);
}

/**
 * The drawn cursors: one band for each line of the selection of each peer, a
 * caret where that selection is collapsed, and a name tag on that caret.
 *
 * This element is inert by construction. It sits *over* the textarea, so an
 * element here that accepted a click would take that click from the user who
 * types below it.
 * 
 * @ignore
 */
function overlay_view(model) {
  return $html.div(
    toList([
      $attribute.attribute("aria-hidden", "true"),
      $attribute.style("position", "absolute"),
      $attribute.style("inset", "0"),
      $attribute.style("overflow", "hidden"),
      $attribute.style("pointer-events", "none"),
    ]),
    $list.flat_map(model.peers, peer_view),
  );
}

/**
 * An invisible copy of the text, with the same layout as the textarea.
 *
 * This element converts the position of a peer into pixels. The browser does
 * not report the position of offset 37 of a `<textarea>` element. There is no
 * API for it, because the text is in a shadow DOM that the page cannot reach.
 * A mirror puts the same string in a normal element, with the same typography
 * and the same wrapping. A DOM `Range` over the text node of that element
 * answers the question directly, and `getClientRects` also splits a selection
 * across several lines into one rectangle for each line.
 *
 * The component renders the text as one child, so the FFI can depend on one
 * text node. The mirror stays in the tree when no peer is present. An empty
 * mirror costs one hidden div, and a mirror that stays in the tree is one that
 * the browser already laid out when the first cursor arrives.
 * 
 * @ignore
 */
function mirror_view(model) {
  return $html.div(
    toList([
      $attribute.attribute(mirror_attribute, model.instance),
      $attribute.attribute("aria-hidden", "true"),
      $attribute.style("position", "absolute"),
      $attribute.style("top", "0"),
      $attribute.style("left", "0"),
      $attribute.style("visibility", "hidden"),
      $attribute.style("pointer-events", "none"),
      $attribute.style("z-index", "-1"),
    ]),
    toList([$html.text(model.value)]),
  );
}

/**
 * One edge of the selection of the element, in UTF-16 code units.
 *
 * This decoder is total, and that is deliberate. Lustre drops an event whose
 * decoder fails. An element that reports no selection, or that reports it as
 * `null`, would thus cost the user a keystroke, and not only a refresh of an
 * anchor. The `unknown_caret` value keeps the edit and skips the anchor
 * step.
 * 
 * @ignore
 */
function caret(name) {
  return $decode.optionally_at(
    toList(["target", name]),
    unknown_caret,
    $decode.one_of($decode.int, toList([$decode.success(unknown_caret)])),
  );
}

/**
 * The whole value of the element, with the caret position after that event.
 * The `input` event and the two composition events all report those two
 * values.
 * 
 * @ignore
 */
function value_decoder(to_msg) {
  return $decode.subfield(
    toList(["target", "value"]),
    $decode.string,
    (value) => {
      return $decode.then$(
        caret("selectionStart"),
        (selection_start) => {
          return $decode.then$(
            caret("selectionEnd"),
            (selection_end) => {
              return $decode.success(
                to_msg(value, selection_start, selection_end),
              );
            },
          );
        },
      );
    },
  );
}

function select_decoder() {
  return $decode.then$(
    caret("selectionStart"),
    (selection_start) => {
      return $decode.then$(
        caret("selectionEnd"),
        (selection_end) => {
          return $decode.success(new UserSelect(selection_start, selection_end));
        },
      );
    },
  );
}

function input_decoder() {
  return value_decoder(
    (var0, var1, var2) => { return new UserInput(var0, var1, var2); },
  );
}

/**
 * A controlled `<textarea>` element that is bound to the channel.
 *
 * The attributes of the caller go on the `<textarea>` element itself, before
 * the attributes of the component. You thus control the presentation, which is
 * `rows`, `placeholder`, `class`, `disabled`, and the ARIA attributes. The
 * value binding, the instance marker, and the event handlers always come from
 * the component. `class` and `style` merge, and they do not replace, so a class
 * from the caller is an addition.
 *
 * **The returned element is a wrapper, and not the textarea.** The component
 * must draw the peer cursors in some element, and a `<textarea>` element
 * renders its own text only, with no highlight and with no caret except the
 * caret of the user. The textarea thus goes inside a box with
 * `position: relative`, beside two elements that it needs and that you must not
 * style. Those two are a hidden mirror, which measures the position of the
 * range of a peer, and an overlay, which holds the drawn cursors. Both are
 * inert, with `aria-hidden` and `pointer-events: none`, and both have no size
 * when no peer is present. The layout still behaves correctly, because the
 * wrapper takes its size from the textarea. But a selector such as
 * `.editor + p` must now look outside the wrapper.
 */
export function view(model, attributes) {
  let bindings = $list.append(
    attributes,
    toList([
      $attribute.attribute(instance_attribute, model.instance),
      $event.on("input", input_decoder()),
      $event.on("select", select_decoder()),
      $event.on("keyup", select_decoder()),
      $event.on("mouseup", select_decoder()),
      $event.on("focus", select_decoder()),
      $event.on(
        "compositionstart",
        value_decoder(
          (var0, var1, var2) => {
            return new CompositionStarted(var0, var1, var2);
          },
        ),
      ),
      $event.on(
        "compositionend",
        value_decoder(
          (var0, var1, var2) => {
            return new CompositionEnded(var0, var1, var2);
          },
        ),
      ),
    ]),
  );
  return $html.div(
    toList([
      $attribute.style("position", "relative"),
      $attribute.style("display", "block"),
    ]),
    toList([
      mirror_view(model),
      overlay_view(model),
      field_view(model, bindings),
    ]),
  );
}

/**
 * The optimistic text that the component renders now.
 */
export function value(model) {
  return model.value;
}

/**
 * The length of the channel, in grapheme clusters. That count is not in code
 * units, and it differs from the result of `string.length` on the rendered
 * value for a surrogate pair.
 */
export function length(model) {
  return model.length;
}

/**
 * The last edit that the runtime refused. The next edit that it accepts clears
 * this value. A refusal means that a peer moved the text below an index that
 * this client already computed. The model took a new snapshot, so the state is
 * consistent. Use this value to tell the user why the keystroke did not
 * apply.
 */
export function error(model) {
  return model.error;
}

/**
 * The current selection of the user, as a half-open grapheme range. The result
 * is `None` before that user places a caret, and after a remote edit deletes
 * the content that both ends were anchored to. A collapsed caret is a range
 * whose two ends are equal.
 *
 * These values are CRDT indices, so you can broadcast them directly. A
 * shared-cursor overlay needs this read.
 */
export function selection(model) {
  return $option.map(
    model.selection,
    (selection) => { return selection.range; },
  );
}

/**
 * The selection of this client, as a pair of anchors, ready for a broadcast.
 * The result is `None` before the user places a caret.
 *
 * Send this value on every [`selection`](#selection) change. The announcement
 * is cheap, and a cursor that moves only when the user *types* looks broken to
 * every other client.
 */
export function cursor(model) {
  return $option.map(
    model.selection,
    (selection) => { return new Cursor(selection.start, selection.end); },
  );
}

function text_anchor_to_json_string(anchor) {
  return $json.to_string($watershed.text_anchor_to_json(anchor));
}

/**
 * Encode a cursor for the wire.
 *
 * The anchors travel as JSON strings inside the object.
 * `watershed.text_anchor_from_json` reads that shape back.
 */
export function cursor_to_json(cursor) {
  return $json.object(
    toList([
      ["start", $json.string(text_anchor_to_json_string(cursor.start))],
      ["end", $json.string(text_anchor_to_json_string(cursor.end))],
    ]),
  );
}

function anchor_decoder() {
  return $decode.then$(
    $decode.string,
    (encoded) => {
      let $ = $watershed.text_anchor_from_json(encoded);
      if ($ instanceof Ok) {
        let anchor$1 = $[0];
        return $decode.success(anchor$1);
      } else {
        return $decode.failure($watershed.text_start_anchor(), "TextAnchor");
      }
    },
  );
}

/**
 * Decode a cursor that [`cursor_to_json`](#cursor_to_json) produced. Put this
 * decoder inside your own decoder for a presence payload.
 */
export function cursor_decoder() {
  return $decode.field(
    "start",
    anchor_decoder(),
    (start) => {
      return $decode.field(
        "end",
        anchor_decoder(),
        (end) => { return $decode.success(new Cursor(start, end)); },
      );
    },
  );
}

/**
 * The cursor of a peer, to draw. `id` must be stable for each user, and the
 * presence user id is the usual choice. That id keeps a measurement attached to
 * the correct peer. `colour` is any CSS colour.
 */
export function peer(id, label, colour, cursor) {
  return new Peer(
    id,
    label,
    colour,
    cursor,
    Option$None$const,
    Option$None$const,
    $List$Empty$const,
  );
}

/**
 * Replace the set of peer cursors that the component draws over the text, and
 * measure them.
 *
 * Call this function from your handler for the presence roster. A peer whose
 * cursor did not move keeps its geometry, so a roster update from another
 * client does not make every cursor flicker.
 */
export function set_peers(model, peers) {
  let peers$1 = $list.map(
    peers,
    (peer) => {
      let $ = $list.find(model.peers, (old) => { return old.id === peer.id; });
      if ($ instanceof Ok) {
        let old = $[0];
        if (isEqual(old.cursor, peer.cursor)) {
          return old;
        } else {
          return peer;
        }
      } else {
        return peer;
      }
    },
  );
  let model$1 = locate(
    new Model(
      model.channel,
      model.backend,
      model.instance,
      model.value,
      model.length,
      model.selection,
      model.composing,
      model.committed,
      model.error,
      model.subscription,
      peers$1,
    ),
  );
  return [model$1, measure(model$1)];
}

/**
 * The channel that the component is bound to, for an edit that the component
 * does not own. Those edits are `text_append`, the anchors, and every other
 * function on `watershed`. To change the channel directly is safe, because the
 * subscription makes the model take a new snapshot.
 */
export function channel(model) {
  return model.channel;
}

/**
 * Release the subscription of a sequenced text binding.
 */
export function stop(model) {
  let $ = model.subscription;
  if ($ instanceof Some) {
    let subscription = $[0];
    return $watershed.unsubscribe(subscription);
  } else {
    return undefined;
  }
}
