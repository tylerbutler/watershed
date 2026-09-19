import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $sequence from "../../lattice_sequence/lattice_sequence/sequence.d.mts";
import type * as $effect from "../../lustre/lustre/effect.d.mts";
import type * as $vattr from "../../lustre/lustre/vdom/vattr.d.mts";
import type * as $vnode from "../../lustre/lustre/vdom/vnode.d.mts";
import type * as $watershed from "../../watershed/watershed.d.mts";
import type * as $crdt_js from "../../watershed/watershed/crdt_js.d.mts";
import type * as $schema from "../../watershed/watershed/schema.d.mts";
import type * as $text_kernel from "../../watershed/watershed/text_kernel.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $grapheme_diff from "../watershed_lustre/grapheme_diff.d.mts";

type DomRoot$ = any;

declare class Backend<CCTJ> extends _.CustomType {
  /** @deprecated */
  constructor(
    snapshot: (x0: CCTJ) => _.Result<[string, number], string>,
    insert: (x0: CCTJ, x1: number, x2: string) => _.Result<undefined, string>,
    delete_range: (x0: CCTJ, x1: number, x2: number) => _.Result<
      undefined,
      string
    >,
    replace_range: (x0: CCTJ, x1: number, x2: number, x3: string) => _.Result<
      undefined,
      string
    >,
    anchor_at: (x0: CCTJ, x1: number, x2: $sequence.Bias$) => _.Result<
      $text_kernel.TextAnchor$,
      undefined
    >,
    resolve_anchor: (x0: CCTJ, x1: $text_kernel.TextAnchor$) => _.Result<
      number,
      undefined
    >
  );
  /** @deprecated */
  snapshot: (x0: CCTJ) => _.Result<[string, number], string>;
  /** @deprecated */
  insert: (x0: CCTJ, x1: number, x2: string) => _.Result<undefined, string>;
  /** @deprecated */
  delete_range: (x0: CCTJ, x1: number, x2: number) => _.Result<
    undefined,
    string
  >;
  /** @deprecated */
  replace_range: (x0: CCTJ, x1: number, x2: number, x3: string) => _.Result<
    undefined,
    string
  >;
  /** @deprecated */
  anchor_at: (x0: CCTJ, x1: number, x2: $sequence.Bias$) => _.Result<
    $text_kernel.TextAnchor$,
    undefined
  >;
  /** @deprecated */
  resolve_anchor: (x0: CCTJ, x1: $text_kernel.TextAnchor$) => _.Result<
    number,
    undefined
  >;
}

type Backend$<CCTJ> = Backend<CCTJ>;

declare class Model<CCTK> extends _.CustomType {
  /** @deprecated */
  constructor(
    channel: CCTK,
    backend: Backend$<CCTK>,
    instance: string,
    value: string,
    length: number,
    selection: $option.Option$<Selection$>,
    composing: $option.Option$<Composition$>,
    committed: $option.Option$<string>,
    error: $option.Option$<string>,
    subscription: $option.Option$<$watershed.SubscriptionToken$>,
    peers: _.List<Peer$>
  );
  /** @deprecated */
  channel: CCTK;
  /** @deprecated */
  backend: Backend$<CCTK>;
  /** @deprecated */
  instance: string;
  /** @deprecated */
  value: string;
  /** @deprecated */
  length: number;
  /** @deprecated */
  selection: $option.Option$<Selection$>;
  /** @deprecated */
  composing: $option.Option$<Composition$>;
  /** @deprecated */
  committed: $option.Option$<string>;
  /** @deprecated */
  error: $option.Option$<string>;
  /** @deprecated */
  subscription: $option.Option$<$watershed.SubscriptionToken$>;
  /** @deprecated */
  peers: _.List<Peer$>;
}

export type Editor$<CCTK> = Model<CCTK>;

declare class Peer extends _.CustomType {
  /** @deprecated */
  constructor(
    id: string,
    label: string,
    colour: string,
    cursor: Cursor$,
    range: $option.Option$<[number, number]>,
    caret: $option.Option$<Rect$>,
    bands: _.List<Rect$>
  );
  /** @deprecated */
  id: string;
  /** @deprecated */
  label: string;
  /** @deprecated */
  colour: string;
  /** @deprecated */
  cursor: Cursor$;
  /** @deprecated */
  range: $option.Option$<[number, number]>;
  /** @deprecated */
  caret: $option.Option$<Rect$>;
  /** @deprecated */
  bands: _.List<Rect$>;
}

export type Peer$ = Peer;

declare class Rect extends _.CustomType {
  /** @deprecated */
  constructor(x: number, y: number, width: number, height: number);
  /** @deprecated */
  x: number;
  /** @deprecated */
  y: number;
  /** @deprecated */
  width: number;
  /** @deprecated */
  height: number;
}

type Rect$ = Rect;

declare class Cursor extends _.CustomType {
  /** @deprecated */
  constructor(start: $text_kernel.TextAnchor$, end: $text_kernel.TextAnchor$);
  /** @deprecated */
  start: $text_kernel.TextAnchor$;
  /** @deprecated */
  end: $text_kernel.TextAnchor$;
}

export type Cursor$ = Cursor;

declare class Composition extends _.CustomType {
  /** @deprecated */
  constructor(
    frozen: string,
    region: [number, number],
    span: _.Result<
      [$text_kernel.TextAnchor$, $text_kernel.TextAnchor$],
      undefined
    >
  );
  /** @deprecated */
  frozen: string;
  /** @deprecated */
  region: [number, number];
  /** @deprecated */
  span: _.Result<
    [$text_kernel.TextAnchor$, $text_kernel.TextAnchor$],
    undefined
  >;
}

type Composition$ = Composition;

declare class Selection extends _.CustomType {
  /** @deprecated */
  constructor(
    start: $text_kernel.TextAnchor$,
    end: $text_kernel.TextAnchor$,
    range: [number, number],
    raw: [number, number]
  );
  /** @deprecated */
  start: $text_kernel.TextAnchor$;
  /** @deprecated */
  end: $text_kernel.TextAnchor$;
  /** @deprecated */
  range: [number, number];
  /** @deprecated */
  raw: [number, number];
}

type Selection$ = Selection;

declare class KernelEvent extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $text_kernel.TextEvent$);
  /** @deprecated */
  0: $text_kernel.TextEvent$;
}

declare class ClassicSubscribed extends _.CustomType {
  /** @deprecated */
  constructor(instance: string, subscription: $watershed.SubscriptionToken$);
  /** @deprecated */
  instance: string;
  /** @deprecated */
  subscription: $watershed.SubscriptionToken$;
}

declare class P2pSubscribed extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $crdt_js.Subscription$);
  /** @deprecated */
  0: $crdt_js.Subscription$;
}

declare class UserInput extends _.CustomType {
  /** @deprecated */
  constructor(value: string, selection_start: number, selection_end: number);
  /** @deprecated */
  value: string;
  /** @deprecated */
  selection_start: number;
  /** @deprecated */
  selection_end: number;
}

declare class UserSelect extends _.CustomType {
  /** @deprecated */
  constructor(selection_start: number, selection_end: number);
  /** @deprecated */
  selection_start: number;
  /** @deprecated */
  selection_end: number;
}

declare class CompositionStarted extends _.CustomType {
  /** @deprecated */
  constructor(value: string, selection_start: number, selection_end: number);
  /** @deprecated */
  value: string;
  /** @deprecated */
  selection_start: number;
  /** @deprecated */
  selection_end: number;
}

declare class CompositionEnded extends _.CustomType {
  /** @deprecated */
  constructor(value: string, selection_start: number, selection_end: number);
  /** @deprecated */
  value: string;
  /** @deprecated */
  selection_start: number;
  /** @deprecated */
  selection_end: number;
}

declare class Measured extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}

export type Msg$ = KernelEvent | ClassicSubscribed | P2pSubscribed | UserInput | UserSelect | CompositionStarted | CompositionEnded | Measured;

export type Model = Editor$<$watershed.SharedText$>;

export type CrdtModel = Editor$<$crdt_js.Handle$<$schema.TextChannel$>>;

export function mutates_document(msg: Msg$): boolean;

export function init(channel: $watershed.SharedText$): [
  Editor$<$watershed.SharedText$>,
  $effect.Effect$<Msg$>
];

export function init_crdt(channel: $crdt_js.Handle$<$schema.TextChannel$>): [
  Editor$<$crdt_js.Handle$<$schema.TextChannel$>>,
  $effect.Effect$<Msg$>
];

export function update<CCTW>(model: Editor$<CCTW>, msg: Msg$): [
  Editor$<CCTW>,
  $effect.Effect$<Msg$>
];

export function view(
  model: Editor$<any>,
  attributes: _.List<$vattr.Attribute$<Msg$>>
): $vnode.Element$<Msg$>;

export function value(model: Editor$<any>): string;

export function length(model: Editor$<any>): number;

export function error(model: Editor$<any>): $option.Option$<string>;

export function selection(model: Editor$<any>): $option.Option$<
  [number, number]
>;

export function cursor(model: Editor$<any>): $option.Option$<Cursor$>;

export function cursor_to_json(cursor: Cursor$): $json.Json$;

export function cursor_decoder(): $decode.Decoder$<Cursor$>;

export function peer(id: string, label: string, colour: string, cursor: Cursor$): Peer$;

export function set_peers<CCVN>(model: Editor$<CCVN>, peers: _.List<Peer$>): [
  Editor$<CCVN>,
  $effect.Effect$<Msg$>
];

export function channel<CCVV>(model: Editor$<CCVV>): CCVV;

export function stop(model: Editor$<$watershed.SharedText$>): undefined;
