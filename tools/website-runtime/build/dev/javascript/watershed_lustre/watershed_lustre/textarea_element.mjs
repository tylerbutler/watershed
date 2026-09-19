/// <reference types="./textarea_element.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dynamic from "../../gleam_stdlib/gleam/dynamic.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $lustre from "../../lustre/lustre.mjs";
import * as $attribute from "../../lustre/lustre/attribute.mjs";
import * as $component from "../../lustre/lustre/component.mjs";
import * as $effect from "../../lustre/lustre/effect.mjs";
import * as $element from "../../lustre/lustre/element.mjs";
import * as $html from "../../lustre/lustre/element/html.mjs";
import * as $event from "../../lustre/lustre/event.mjs";
import * as $watershed from "../../watershed/watershed.mjs";
import {
  Ok,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  isEqual,
} from "../gleam.mjs";
import * as $textarea from "../watershed_lustre/textarea.mjs";
import {
  sharedTextPropertyToSharedText as shared_text_property_to_shared_text,
  identity as shared_text_to_json,
} from "./textarea_element_ffi.mjs";

class Model extends $CustomType {
  constructor(editor, peers, announced, rows, columns, placeholder, disabled) {
    super();
    this.editor = editor;
    this.peers = peers;
    this.announced = announced;
    this.rows = rows;
    this.columns = columns;
    this.placeholder = placeholder;
    this.disabled = disabled;
  }
}

class ChannelReceived extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

class PeersReceived extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

class RowsChanged extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

class ColumnsChanged extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

class PlaceholderChanged extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

class DisabledChanged extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

class Inner extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}

class SharedTextProperty extends $CustomType {
  constructor(value) {
    super();
    this.value = value;
  }
}

/**
 * The registered tag. The name of a custom element must contain a hyphen.
 * This name is fixed, so a host and a stylesheet can depend on it.
 */
export const name = "watershed-textarea";

function count(to_msg) {
  return (value) => {
    return new Ok(to_msg($option.from_result($int.parse(value))));
  };
}

function peers_decoder() {
  let _pipe = $decode.list(
    $decode.field(
      "id",
      $decode.string,
      (id) => {
        return $decode.field(
          "label",
          $decode.string,
          (label) => {
            return $decode.field(
              "colour",
              $decode.string,
              (colour) => {
                return $decode.field(
                  "cursor",
                  $textarea.cursor_decoder(),
                  (cursor) => {
                    return $decode.success(
                      $textarea.peer(id, label, colour, cursor),
                    );
                  },
                );
              },
            );
          },
        );
      },
    ),
  );
  return $decode.map(_pipe, (var0) => { return new PeersReceived(var0); });
}

/**
 * Accept a live `SharedText` value from the `channel` property. The decoder
 * checks the shape before the coercion: a handle carries its channel
 * `address` and the `runtime` that it is bound to. A value without those two
 * fields decodes to nothing, and the component ignores the assignment. That
 * behaviour contains the fault, and the component does not crash on an
 * invalid value.
 * 
 * @ignore
 */
function channel_decoder() {
  return $decode.field(
    "address",
    $decode.string,
    (_) => {
      return $decode.field(
        "runtime",
        $decode.dynamic,
        (_) => {
          return $decode.then$(
            $decode.dynamic,
            (handle) => {
              let property = new SharedTextProperty(handle);
              return $decode.success(
                new ChannelReceived(
                  shared_text_property_to_shared_text(property),
                ),
              );
            },
          );
        },
      );
    },
  );
}

function options() {
  return toList([
    $component.on_property_change("channel", channel_decoder()),
    $component.on_property_change("peers", peers_decoder()),
    $component.on_attribute_change(
      "rows",
      count((var0) => { return new RowsChanged(var0); }),
    ),
    $component.on_attribute_change(
      "cols",
      count((var0) => { return new ColumnsChanged(var0); }),
    ),
    $component.on_attribute_change(
      "placeholder",
      (value) => {
        return new Ok(
          new PlaceholderChanged(
            (() => {
              if (value === "") {
                return Option$None$const;
              } else {
                let text = value;
                return new Some(text);
              }
            })(),
          ),
        );
      },
    ),
    $component.on_attribute_change(
      "disabled",
      (value) => { return new Ok(new DisabledChanged(value === "true")); },
    ),
    $component.delegates_focus(true),
  ]);
}

function passthrough(model) {
  let attributes = toList([$component.part("textarea")]);
  let _block;
  let $ = model.disabled;
  if ($) {
    _block = listPrepend($attribute.disabled(true), attributes);
  } else {
    _block = attributes;
  }
  let attributes$1 = _block;
  let _block$1;
  let $1 = model.placeholder;
  if ($1 instanceof Some) {
    let text = $1[0];
    _block$1 = listPrepend($attribute.placeholder(text), attributes$1);
  } else {
    _block$1 = attributes$1;
  }
  let attributes$2 = _block$1;
  let _block$2;
  let $2 = model.columns;
  if ($2 instanceof Some) {
    let columns = $2[0];
    _block$2 = listPrepend($attribute.cols(columns), attributes$2);
  } else {
    _block$2 = attributes$2;
  }
  let attributes$3 = _block$2;
  let $3 = model.rows;
  if ($3 instanceof Some) {
    let rows = $3[0];
    return listPrepend($attribute.rows(rows), attributes$3);
  } else {
    return attributes$3;
  }
}

/**
 * The `channel` property as a typed attribute, for a host that renders the tag
 * itself. This is the one unsafe seam of the module. The live handle passes
 * through as a property value, and the other side checks its shape first.
 */
export function channel_property(channel) {
  return $attribute.property("channel", shared_text_to_json(channel));
}

/**
 * Render the element from a Lustre host, with the channel attached. Each
 * other attribute goes on the *host* element. To style the inner textarea, use
 * the `rows`, `cols`, and `placeholder` attributes, or `::part(textarea)`.
 */
export function element(channel, attributes) {
  return $element.element(
    name,
    listPrepend(channel_property(channel), attributes),
    $List$Empty$const,
  );
}

function view(model) {
  let $ = model.editor;
  if ($ instanceof Some) {
    let editor = $[0];
    let _pipe = $textarea.view(editor, passthrough(model));
    return $element.map(_pipe, (var0) => { return new Inner(var0); });
  } else {
    return $html.textarea(
      listPrepend($attribute.disabled(true), passthrough(model)),
      "",
    );
  }
}

function changed(editor) {
  return $event.emit(
    "change",
    $json.object(
      toList([
        ["value", $json.string($textarea.value(editor))],
        ["length", $json.int($textarea.length(editor))],
      ]),
    ),
  );
}

/**
 * The accessors of the triple, as events at the element boundary. Each event
 * occurs on a real transition only. A host that repaints on `"change"` thus
 * does not repaint on every `keyup`.
 * 
 * @ignore
 */
function emitted(before, after, announced) {
  let _block;
  let $ = $textarea.value(after) === $textarea.value(before);
  if ($) {
    _block = $effect.none();
  } else {
    _block = changed(after);
  }
  let change = _block;
  let _block$1;
  let $1 = isEqual($textarea.error(after), $textarea.error(before));
  if ($1) {
    _block$1 = $effect.none();
  } else {
    _block$1 = $event.emit(
      "error",
      $json.object(
        toList([
          ["message", $json.nullable($textarea.error(after), $json.string)],
        ]),
      ),
    );
  }
  let errored = _block$1;
  let cursor = $textarea.cursor(after);
  let _block$2;
  let $3 = isEqual(cursor, announced);
  if ($3) {
    _block$2 = [announced, $effect.none()];
  } else {
    _block$2 = [
      cursor,
      $event.emit(
        "cursor",
        (() => {
          if (cursor instanceof Some) {
            let cursor$1 = cursor[0];
            return $textarea.cursor_to_json(cursor$1);
          } else {
            return $json.null$();
          }
        })(),
      ),
    ];
  }
  let $2 = _block$2;
  let announced$1 = $2[0];
  let moved = $2[1];
  return [announced$1, $effect.batch(toList([change, errored, moved]))];
}

function update(model, msg) {
  if (msg instanceof ChannelReceived) {
    let channel = msg[0];
    let _block;
    let $ = model.editor;
    if ($ instanceof Some) {
      let editor = $[0];
      _block = !isEqual($textarea.channel(editor), channel);
    } else {
      _block = true;
    }
    let rebound = _block;
    if (rebound) {
      let $1 = $textarea.init(channel);
      let editor = $1[0];
      let started = $1[1];
      let _block$1;
      let $3 = model.peers;
      if ($3 instanceof $Empty) {
        _block$1 = [editor, $effect.none()];
      } else {
        let roster = $3;
        _block$1 = $textarea.set_peers(editor, roster);
      }
      let $2 = _block$1;
      let editor$1 = $2[0];
      let placed = $2[1];
      return [
        new Model(
          new Some(editor$1),
          model.peers,
          Option$None$const,
          model.rows,
          model.columns,
          model.placeholder,
          model.disabled,
        ),
        $effect.batch(
          toList([
            $effect.map(started, (var0) => { return new Inner(var0); }),
            $effect.map(placed, (var0) => { return new Inner(var0); }),
            changed(editor$1),
          ]),
        ),
      ];
    } else {
      return [model, $effect.none()];
    }
  } else if (msg instanceof PeersReceived) {
    let roster = msg[0];
    let $ = model.editor;
    if ($ instanceof Some) {
      let editor = $[0];
      let $1 = $textarea.set_peers(editor, roster);
      let editor$1 = $1[0];
      let editor_effect = $1[1];
      return [
        new Model(
          new Some(editor$1),
          roster,
          model.announced,
          model.rows,
          model.columns,
          model.placeholder,
          model.disabled,
        ),
        $effect.map(editor_effect, (var0) => { return new Inner(var0); }),
      ];
    } else {
      return [
        new Model(
          model.editor,
          roster,
          model.announced,
          model.rows,
          model.columns,
          model.placeholder,
          model.disabled,
        ),
        $effect.none(),
      ];
    }
  } else if (msg instanceof RowsChanged) {
    let rows = msg[0];
    return [
      new Model(
        model.editor,
        model.peers,
        model.announced,
        rows,
        model.columns,
        model.placeholder,
        model.disabled,
      ),
      $effect.none(),
    ];
  } else if (msg instanceof ColumnsChanged) {
    let columns = msg[0];
    return [
      new Model(
        model.editor,
        model.peers,
        model.announced,
        model.rows,
        columns,
        model.placeholder,
        model.disabled,
      ),
      $effect.none(),
    ];
  } else if (msg instanceof PlaceholderChanged) {
    let placeholder = msg[0];
    return [
      new Model(
        model.editor,
        model.peers,
        model.announced,
        model.rows,
        model.columns,
        placeholder,
        model.disabled,
      ),
      $effect.none(),
    ];
  } else if (msg instanceof DisabledChanged) {
    let disabled = msg[0];
    return [
      new Model(
        model.editor,
        model.peers,
        model.announced,
        model.rows,
        model.columns,
        model.placeholder,
        disabled,
      ),
      $effect.none(),
    ];
  } else {
    let inner = msg[0];
    let $ = model.editor;
    if ($ instanceof Some) {
      let editor = $[0];
      let $1 = $textarea.update(editor, inner);
      let after = $1[0];
      let editor_effect = $1[1];
      let $2 = emitted(editor, after, model.announced);
      let announced = $2[0];
      let events = $2[1];
      return [
        new Model(
          new Some(after),
          model.peers,
          announced,
          model.rows,
          model.columns,
          model.placeholder,
          model.disabled,
        ),
        $effect.batch(
          toList([
            $effect.map(editor_effect, (var0) => { return new Inner(var0); }),
            events,
          ]),
        ),
      ];
    } else {
      return [model, $effect.none()];
    }
  }
}

function init(_) {
  return [
    new Model(
      Option$None$const,
      $List$Empty$const,
      Option$None$const,
      Option$None$const,
      Option$None$const,
      Option$None$const,
      false,
    ),
    $effect.none(),
  ];
}

/**
 * Define `<watershed-textarea>` in the custom element registry of the browser.
 * Call this function one time at startup, before you create or render an
 * instance. The module docs explain why the order is important. The function
 * fails with `ComponentAlreadyRegistered` on a second call, and with
 * `NotABrowser` outside a browser.
 */
export function register() {
  return $lustre.register(
    $lustre.component(init, update, view, options()),
    name,
  );
}

/**
 * One peer cursor, in the wire shape of the `peers` property. `id` must be
 * stable for each user. `colour` is any CSS colour. `cursor` is the value that
 * you decoded from your presence channel, which is the `"cursor"` event detail
 * of the other side.
 */
export function peer(id, label, colour, cursor) {
  return $json.object(
    toList([
      ["id", $json.string(id)],
      ["label", $json.string(label)],
      ["colour", $json.string(colour)],
      ["cursor", $textarea.cursor_to_json(cursor)],
    ]),
  );
}

/**
 * The `peers` property as a typed attribute: the full roster to draw, which
 * you build with [`peer`](#peer). It replaces the whole previous roster, the
 * same as [`textarea.set_peers`](./textarea.html#set_peers), because it is
 * that function.
 */
export function peers(peers) {
  return $attribute.property("peers", $json.preprocessed_array(peers));
}
