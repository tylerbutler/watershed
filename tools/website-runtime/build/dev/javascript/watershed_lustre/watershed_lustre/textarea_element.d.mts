import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $lustre from "../../lustre/lustre.d.mts";
import type * as $effect from "../../lustre/lustre/effect.d.mts";
import type * as $app from "../../lustre/lustre/runtime/app.d.mts";
import type * as $vattr from "../../lustre/lustre/vdom/vattr.d.mts";
import type * as $vnode from "../../lustre/lustre/vdom/vnode.d.mts";
import type * as $watershed from "../../watershed/watershed.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $textarea from "../watershed_lustre/textarea.d.mts";

declare class Model extends _.CustomType {
  /** @deprecated */
  constructor(
    editor: $option.Option$<$textarea.Editor$<$watershed.SharedText$>>,
    peers: _.List<$textarea.Peer$>,
    announced: $option.Option$<$textarea.Cursor$>,
    rows: $option.Option$<number>,
    columns: $option.Option$<number>,
    placeholder: $option.Option$<string>,
    disabled: boolean
  );
  /** @deprecated */
  editor: $option.Option$<$textarea.Editor$<$watershed.SharedText$>>;
  /** @deprecated */
  peers: _.List<$textarea.Peer$>;
  /** @deprecated */
  announced: $option.Option$<$textarea.Cursor$>;
  /** @deprecated */
  rows: $option.Option$<number>;
  /** @deprecated */
  columns: $option.Option$<number>;
  /** @deprecated */
  placeholder: $option.Option$<string>;
  /** @deprecated */
  disabled: boolean;
}

type Model$ = Model;

declare class ChannelReceived extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $watershed.SharedText$);
  /** @deprecated */
  0: $watershed.SharedText$;
}

declare class PeersReceived extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: _.List<$textarea.Peer$>);
  /** @deprecated */
  0: _.List<$textarea.Peer$>;
}

declare class RowsChanged extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $option.Option$<number>);
  /** @deprecated */
  0: $option.Option$<number>;
}

declare class ColumnsChanged extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $option.Option$<number>);
  /** @deprecated */
  0: $option.Option$<number>;
}

declare class PlaceholderChanged extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $option.Option$<string>);
  /** @deprecated */
  0: $option.Option$<string>;
}

declare class DisabledChanged extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: boolean);
  /** @deprecated */
  0: boolean;
}

declare class Inner extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $textarea.Msg$);
  /** @deprecated */
  0: $textarea.Msg$;
}

type Msg$ = ChannelReceived | PeersReceived | RowsChanged | ColumnsChanged | PlaceholderChanged | DisabledChanged | Inner;

declare class SharedTextProperty extends _.CustomType {
  /** @deprecated */
  constructor(value: $dynamic.Dynamic$);
  /** @deprecated */
  value: $dynamic.Dynamic$;
}

type SharedTextProperty$ = SharedTextProperty;

export const name: string;

export function channel_property(channel: $watershed.SharedText$): $vattr.Attribute$<
  any
>;

export function element<CEDW>(
  channel: $watershed.SharedText$,
  attributes: _.List<$vattr.Attribute$<CEDW>>
): $vnode.Element$<CEDW>;

export function register(): _.Result<undefined, $lustre.Error$>;

export function peer(
  id: string,
  label: string,
  colour: string,
  cursor: $textarea.Cursor$
): $json.Json$;

export function peers(peers: _.List<$json.Json$>): $vattr.Attribute$<any>;
