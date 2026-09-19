import type * as $dynamic from "../../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $decode from "../../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as _ from "../../gleam.d.mts";
import type * as $mutable_map from "../../lustre/internals/mutable_map.d.mts";
import type * as $path from "../../lustre/vdom/path.d.mts";
import type * as $vattr from "../../lustre/vdom/vattr.d.mts";
import type * as $vnode from "../../lustre/vdom/vnode.d.mts";

declare class Cache<WTB> extends _.CustomType {
  /** @deprecated */
  constructor(
    events: Events$<WTB>,
    vdoms: $mutable_map.MutableMap$<
      () => $vnode.Element$<WTB>,
      $vnode.Element$<WTB>
    >,
    old_vdoms: $mutable_map.MutableMap$<
      () => $vnode.Element$<WTB>,
      $vnode.Element$<WTB>
    >,
    dispatched_paths: _.List<string>,
    next_dispatched_paths: _.List<string>
  );
  /** @deprecated */
  events: Events$<WTB>;
  /** @deprecated */
  vdoms: $mutable_map.MutableMap$<
    () => $vnode.Element$<WTB>,
    $vnode.Element$<WTB>
  >;
  /** @deprecated */
  old_vdoms: $mutable_map.MutableMap$<
    () => $vnode.Element$<WTB>,
    $vnode.Element$<WTB>
  >;
  /** @deprecated */
  dispatched_paths: _.List<string>;
  /** @deprecated */
  next_dispatched_paths: _.List<string>;
}

export type Cache$<WTB> = Cache<WTB>;

declare class Events<WTC> extends _.CustomType {
  /** @deprecated */
  constructor(
    handlers: $mutable_map.MutableMap$<
      string,
      $decode.Decoder$<$vattr.Handler$<WTC>>
    >,
    children: $mutable_map.MutableMap$<string, Child$<WTC>>
  );
  /** @deprecated */
  handlers: $mutable_map.MutableMap$<
    string,
    $decode.Decoder$<$vattr.Handler$<WTC>>
  >;
  /** @deprecated */
  children: $mutable_map.MutableMap$<string, Child$<WTC>>;
}

export type Events$<WTC> = Events<WTC>;

declare class Child<WTD> extends _.CustomType {
  /** @deprecated */
  constructor(
    mapper: (x0: $dynamic.Dynamic$) => $dynamic.Dynamic$,
    events: Events$<WTD>
  );
  /** @deprecated */
  mapper: (x0: $dynamic.Dynamic$) => $dynamic.Dynamic$;
  /** @deprecated */
  events: Events$<WTD>;
}

type Child$<WTD> = Child<WTD>;

declare class AddedChildren<WTE> extends _.CustomType {
  /** @deprecated */
  constructor(
    handlers: $mutable_map.MutableMap$<
      string,
      $decode.Decoder$<$vattr.Handler$<WTE>>
    >,
    children: $mutable_map.MutableMap$<string, Child$<WTE>>,
    vdoms: $mutable_map.MutableMap$<
      () => $vnode.Element$<WTE>,
      $vnode.Element$<WTE>
    >
  );
  /** @deprecated */
  handlers: $mutable_map.MutableMap$<
    string,
    $decode.Decoder$<$vattr.Handler$<WTE>>
  >;
  /** @deprecated */
  children: $mutable_map.MutableMap$<string, Child$<WTE>>;
  /** @deprecated */
  vdoms: $mutable_map.MutableMap$<
    () => $vnode.Element$<WTE>,
    $vnode.Element$<WTE>
  >;
}

type AddedChildren$<WTE> = AddedChildren<WTE>;

declare class DecodedEvent<WTF> extends _.CustomType {
  /** @deprecated */
  constructor(path: string, handler: $vattr.Handler$<WTF>);
  /** @deprecated */
  path: string;
  /** @deprecated */
  handler: $vattr.Handler$<WTF>;
}

declare class DispatchedEvent extends _.CustomType {
  /** @deprecated */
  constructor(path: string);
  /** @deprecated */
  path: string;
}

export type DecodedEvent$<WTF> = DecodedEvent<WTF> | DispatchedEvent;

export type Mapper = (x0: $dynamic.Dynamic$) => $dynamic.Dynamic$;

export function compose_mapper(
  mapper: (x0: $dynamic.Dynamic$) => $dynamic.Dynamic$,
  child_mapper: (x0: $dynamic.Dynamic$) => $dynamic.Dynamic$
): (x0: $dynamic.Dynamic$) => $dynamic.Dynamic$;

export function new_events(): Events$<any>;

export function new$(): Cache$<any>;

export function add_children<WWP>(
  cache: Cache$<WWP>,
  events: Events$<WWP>,
  path: $path.Path$,
  child_index: number,
  nodes: _.List<$vnode.Element$<WWP>>
): [Cache$<WWP>, Events$<WWP>];

export function add_child<WVY>(
  cache: Cache$<WVY>,
  events: Events$<WVY>,
  parent: $path.Path$,
  index: number,
  child: $vnode.Element$<WVY>
): [Cache$<WVY>, Events$<WVY>];

export function from_node<WTK>(root: $vnode.Element$<WTK>): Cache$<WTK>;

export function tick<WTN>(cache: Cache$<WTN>): Cache$<WTN>;

export function events<WTQ>(cache: Cache$<WTQ>): Events$<WTQ>;

export function update_events<WTT>(cache: Cache$<WTT>, events: Events$<WTT>): Cache$<
  WTT
>;

export function memos<WTX>(cache: Cache$<WTX>): $mutable_map.MutableMap$<
  () => $vnode.Element$<WTX>,
  $vnode.Element$<WTX>
>;

export function get_old_memo<WUA>(
  cache: Cache$<WUA>,
  old: () => $vnode.Element$<WUA>,
  new$: () => $vnode.Element$<WUA>
): $vnode.Element$<WUA>;

export function keep_memo<WUF>(
  cache: Cache$<WUF>,
  old: () => $vnode.Element$<WUF>,
  new$: () => $vnode.Element$<WUF>
): Cache$<WUF>;

export function add_memo<WUK>(
  cache: Cache$<WUK>,
  new$: () => $vnode.Element$<WUK>,
  node: $vnode.Element$<WUK>
): Cache$<WUK>;

export function get_subtree<WUP>(
  events: Events$<WUP>,
  path: string,
  old_mapper: (x0: $dynamic.Dynamic$) => $dynamic.Dynamic$
): Events$<WUP>;

export function update_subtree<WUS>(
  parent: Events$<WUS>,
  path: string,
  mapper: (x0: $dynamic.Dynamic$) => $dynamic.Dynamic$,
  events: Events$<WUS>
): Events$<WUS>;

export function add_event<WUW>(
  events: Events$<WUW>,
  path: $path.Path$,
  name: string,
  handler: $decode.Decoder$<$vattr.Handler$<WUW>>
): Events$<WUW>;

export function remove_event<WVM>(
  events: Events$<WVM>,
  path: $path.Path$,
  name: string
): Events$<WVM>;

export function remove_child<WXI>(
  cache: Cache$<WXI>,
  events: Events$<WXI>,
  parent: $path.Path$,
  child_index: number,
  child: $vnode.Element$<WXI>
): Events$<WXI>;

export function replace_child<WYK>(
  cache: Cache$<WYK>,
  events: Events$<WYK>,
  parent: $path.Path$,
  child_index: number,
  prev: $vnode.Element$<WYK>,
  next: $vnode.Element$<WYK>
): [Cache$<WYK>, Events$<WYK>];

export function decode(
  cache: Cache$<any>,
  path: string,
  name: string,
  event: $dynamic.Dynamic$
): DecodedEvent$<any>;

export function dispatch<WYY>(cache: Cache$<WYY>, event: DecodedEvent$<WYY>): [
  Cache$<WYY>,
  _.Result<$vattr.Handler$<WYY>, undefined>
];

export function handle<WZC>(
  cache: Cache$<WZC>,
  path: string,
  name: string,
  event: $dynamic.Dynamic$
): [Cache$<WZC>, _.Result<$vattr.Handler$<WZC>, undefined>];

export function has_dispatched_events(cache: Cache$<any>, path: $path.Path$): boolean;
