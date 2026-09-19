import type * as $json from "../../../gleam_json/gleam/json.d.mts";
import type * as $dynamic from "../../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $string_tree from "../../../gleam_stdlib/gleam/string_tree.d.mts";
import type * as _ from "../../gleam.d.mts";
import type * as $mutable_map from "../../lustre/internals/mutable_map.d.mts";
import type * as $ref from "../../lustre/internals/ref.d.mts";
import type * as $vattr from "../../lustre/vdom/vattr.d.mts";

export class Fragment<UNP> extends _.CustomType {
  /** @deprecated */
  constructor(
    kind: number,
    key: string,
    children: _.List<Element$<UNP>>,
    keyed_children: $mutable_map.MutableMap$<string, Element$<UNP>>
  );
  /** @deprecated */
  kind: number;
  /** @deprecated */
  key: string;
  /** @deprecated */
  children: _.List<Element$<UNP>>;
  /** @deprecated */
  keyed_children: $mutable_map.MutableMap$<string, Element$<UNP>>;
}
export function Element$Fragment<UNP>(
  kind: number,
  key: string,
  children: _.List<Element$<UNP>>,
  keyed_children: $mutable_map.MutableMap$<string, Element$<UNP>>,
): Element$<UNP>;
export function Element$isFragment<UNP>(value: any): value is Element$<unknown>;
export function Element$Fragment$0<UNP>(value: Element$<UNP>): number;
export function Element$Fragment$kind<UNP>(value: Element$<UNP>): number;
export function Element$Fragment$1<UNP>(value: Element$<UNP>): string;
export function Element$Fragment$key<UNP>(value: Element$<UNP>): string;
export function Element$Fragment$2<UNP>(value: Element$<UNP>): _.List<
  Element$<UNP>
>;
export function Element$Fragment$children<UNP>(value: Element$<UNP>): _.List<
  Element$<UNP>
>;
export function Element$Fragment$3<UNP>(value: Element$<UNP>): $mutable_map.MutableMap$<
  string,
  Element$<UNP>
>;
export function Element$Fragment$keyed_children<UNP>(value: Element$<UNP>): $mutable_map.MutableMap$<
  string,
  Element$<UNP>
>;

export class Element<UNP> extends _.CustomType {
  /** @deprecated */
  constructor(
    kind: number,
    key: string,
    namespace: string,
    tag: string,
    attributes: _.List<$vattr.Attribute$<UNP>>,
    children: _.List<Element$<UNP>>,
    keyed_children: $mutable_map.MutableMap$<string, Element$<UNP>>,
    self_closing: boolean,
    void$: boolean
  );
  /** @deprecated */
  kind: number;
  /** @deprecated */
  key: string;
  /** @deprecated */
  namespace: string;
  /** @deprecated */
  tag: string;
  /** @deprecated */
  attributes: _.List<$vattr.Attribute$<UNP>>;
  /** @deprecated */
  children: _.List<Element$<UNP>>;
  /** @deprecated */
  keyed_children: $mutable_map.MutableMap$<string, Element$<UNP>>;
  /** @deprecated */
  self_closing: boolean;
  /** @deprecated */
  void: boolean;
}
export function Element$Element<UNP>(
  kind: number,
  key: string,
  namespace: string,
  tag: string,
  attributes: _.List<$vattr.Attribute$<UNP>>,
  children: _.List<Element$<UNP>>,
  keyed_children: $mutable_map.MutableMap$<string, Element$<UNP>>,
  self_closing: boolean,
  void$: boolean,
): Element$<UNP>;
export function Element$isElement<UNP>(value: any): value is Element$<unknown>;
export function Element$Element$0<UNP>(value: Element$<UNP>): number;
export function Element$Element$kind<UNP>(value: Element$<UNP>): number;
export function Element$Element$1<UNP>(value: Element$<UNP>): string;
export function Element$Element$key<UNP>(value: Element$<UNP>): string;
export function Element$Element$2<UNP>(value: Element$<UNP>): string;
export function Element$Element$namespace<UNP>(value: Element$<UNP>): string;
export function Element$Element$3<UNP>(value: Element$<UNP>): string;
export function Element$Element$tag<UNP>(value: Element$<UNP>): string;
export function Element$Element$4<UNP>(value: Element$<UNP>): _.List<
  $vattr.Attribute$<UNP>
>;
export function Element$Element$attributes<UNP>(value: Element$<UNP>): _.List<
  $vattr.Attribute$<UNP>
>;
export function Element$Element$5<UNP>(value: Element$<UNP>): _.List<
  Element$<UNP>
>;
export function Element$Element$children<UNP>(value: Element$<UNP>): _.List<
  Element$<UNP>
>;
export function Element$Element$6<UNP>(value: Element$<UNP>): $mutable_map.MutableMap$<
  string,
  Element$<UNP>
>;
export function Element$Element$keyed_children<UNP>(value: Element$<UNP>): $mutable_map.MutableMap$<
  string,
  Element$<UNP>
>;
export function Element$Element$7<UNP>(value: Element$<UNP>): boolean;
export function Element$Element$self_closing<UNP>(value: Element$<UNP>): boolean;
export function Element$Element$8<UNP>(
  value: Element$<UNP>,
): boolean;
export function Element$Element$void<UNP>(value: Element$<UNP>): boolean;

export class Text extends _.CustomType {
  /** @deprecated */
  constructor(kind: number, key: string, content: string);
  /** @deprecated */
  kind: number;
  /** @deprecated */
  key: string;
  /** @deprecated */
  content: string;
}
export function Element$Text<UNP>(
  kind: number,
  key: string,
  content: string,
): Element$<UNP>;
export function Element$isText<UNP>(value: any): value is Element$<unknown>;
export function Element$Text$0<UNP>(value: Element$<UNP>): number;
export function Element$Text$kind<UNP>(value: Element$<UNP>): number;
export function Element$Text$1<UNP>(value: Element$<UNP>): string;
export function Element$Text$key<UNP>(value: Element$<UNP>): string;
export function Element$Text$2<UNP>(value: Element$<UNP>): string;
export function Element$Text$content<UNP>(value: Element$<UNP>): string;

export class UnsafeInnerHtml<UNP> extends _.CustomType {
  /** @deprecated */
  constructor(
    kind: number,
    key: string,
    namespace: string,
    tag: string,
    attributes: _.List<$vattr.Attribute$<UNP>>,
    inner_html: string
  );
  /** @deprecated */
  kind: number;
  /** @deprecated */
  key: string;
  /** @deprecated */
  namespace: string;
  /** @deprecated */
  tag: string;
  /** @deprecated */
  attributes: _.List<$vattr.Attribute$<UNP>>;
  /** @deprecated */
  inner_html: string;
}
export function Element$UnsafeInnerHtml<UNP>(
  kind: number,
  key: string,
  namespace: string,
  tag: string,
  attributes: _.List<$vattr.Attribute$<UNP>>,
  inner_html: string,
): Element$<UNP>;
export function Element$isUnsafeInnerHtml<UNP>(
  value: any,
): value is Element$<unknown>;
export function Element$UnsafeInnerHtml$0<UNP>(value: Element$<UNP>): number;
export function Element$UnsafeInnerHtml$kind<UNP>(value: Element$<UNP>): number;
export function Element$UnsafeInnerHtml$1<UNP>(value: Element$<UNP>): string;
export function Element$UnsafeInnerHtml$key<UNP>(value: Element$<UNP>): string;
export function Element$UnsafeInnerHtml$2<UNP>(value: Element$<UNP>): string;
export function Element$UnsafeInnerHtml$namespace<UNP>(value: Element$<UNP>): string;
export function Element$UnsafeInnerHtml$3<UNP>(
  value: Element$<UNP>,
): string;
export function Element$UnsafeInnerHtml$tag<UNP>(value: Element$<UNP>): string;
export function Element$UnsafeInnerHtml$4<UNP>(value: Element$<UNP>): _.List<
  $vattr.Attribute$<UNP>
>;
export function Element$UnsafeInnerHtml$attributes<UNP>(value: Element$<UNP>): _.List<
  $vattr.Attribute$<UNP>
>;
export function Element$UnsafeInnerHtml$5<UNP>(value: Element$<UNP>): string;
export function Element$UnsafeInnerHtml$inner_html<UNP>(value: Element$<UNP>): string;

export class Map<UNP> extends _.CustomType {
  /** @deprecated */
  constructor(
    kind: number,
    key: string,
    mapper: (x0: $dynamic.Dynamic$) => $dynamic.Dynamic$,
    child: Element$<UNP>
  );
  /** @deprecated */
  kind: number;
  /** @deprecated */
  key: string;
  /** @deprecated */
  mapper: (x0: $dynamic.Dynamic$) => $dynamic.Dynamic$;
  /** @deprecated */
  child: Element$<UNP>;
}
export function Element$Map<UNP>(
  kind: number,
  key: string,
  mapper: (x0: $dynamic.Dynamic$) => $dynamic.Dynamic$,
  child: Element$<UNP>,
): Element$<UNP>;
export function Element$isMap<UNP>(value: any): value is Element$<unknown>;
export function Element$Map$0<UNP>(value: Element$<UNP>): number;
export function Element$Map$kind<UNP>(value: Element$<UNP>): number;
export function Element$Map$1<UNP>(value: Element$<UNP>): string;
export function Element$Map$key<UNP>(value: Element$<UNP>): string;
export function Element$Map$2<UNP>(value: Element$<UNP>): (
  x0: $dynamic.Dynamic$
) => $dynamic.Dynamic$;
export function Element$Map$mapper<UNP>(value: Element$<UNP>): (
  x0: $dynamic.Dynamic$
) => $dynamic.Dynamic$;
export function Element$Map$3<UNP>(value: Element$<UNP>): Element$<UNP>;
export function Element$Map$child<UNP>(value: Element$<UNP>): Element$<UNP>;

export class Memo<UNP> extends _.CustomType {
  /** @deprecated */
  constructor(
    kind: number,
    key: string,
    dependencies: _.List<$ref.Ref$>,
    view: () => Element$<UNP>
  );
  /** @deprecated */
  kind: number;
  /** @deprecated */
  key: string;
  /** @deprecated */
  dependencies: _.List<$ref.Ref$>;
  /** @deprecated */
  view: () => Element$<UNP>;
}
export function Element$Memo<UNP>(
  kind: number,
  key: string,
  dependencies: _.List<$ref.Ref$>,
  view: () => Element$<UNP>,
): Element$<UNP>;
export function Element$isMemo<UNP>(value: any): value is Element$<unknown>;
export function Element$Memo$0<UNP>(value: Element$<UNP>): number;
export function Element$Memo$kind<UNP>(value: Element$<UNP>): number;
export function Element$Memo$1<UNP>(value: Element$<UNP>): string;
export function Element$Memo$key<UNP>(value: Element$<UNP>): string;
export function Element$Memo$2<UNP>(value: Element$<UNP>): _.List<$ref.Ref$>;
export function Element$Memo$dependencies<UNP>(value: Element$<UNP>): _.List<
  $ref.Ref$
>;
export function Element$Memo$3<UNP>(value: Element$<UNP>): () => Element$<UNP>;
export function Element$Memo$view<UNP>(value: Element$<UNP>): () => Element$<
  UNP
>;

export type Element$<UNP> = Fragment<UNP> | Element<UNP> | Text | UnsafeInnerHtml<
  UNP
> | Map<UNP> | Memo<UNP>;

export function Element$key<UNP>(value: Element$<UNP>): string;
export function Element$kind<UNP>(value: Element$<UNP>): number;

export type Memos = $mutable_map.MutableMap$<() => Element$<any>, Element$<any>>;

export type View = () => Element$<any>;

export const fragment_kind: number;

export const element_kind: number;

export const text_kind: number;

export const unsafe_inner_html_kind: number;

export const map_kind: number;

export const memo_kind: number;

export function fragment<UNX>(
  key: string,
  children: _.List<Element$<UNX>>,
  keyed_children: $mutable_map.MutableMap$<string, Element$<UNX>>
): Element$<UNX>;

export function element<UOE>(
  key: string,
  namespace: string,
  tag: string,
  attributes: _.List<$vattr.Attribute$<UOE>>,
  children: _.List<Element$<UOE>>,
  keyed_children: $mutable_map.MutableMap$<string, Element$<UOE>>,
  self_closing: boolean,
  void$: boolean
): Element$<UOE>;

export function is_void_html_element(tag: string, namespace: string): boolean;

export function text(key: string, content: string): Element$<any>;

export function unsafe_inner_html<UOP>(
  key: string,
  namespace: string,
  tag: string,
  attributes: _.List<$vattr.Attribute$<UOP>>,
  inner_html: string
): Element$<UOP>;

export function map<UOT, UOV>(element: Element$<UOT>, mapper: (x0: UOT) => UOV): Element$<
  UOV
>;

export function memo<UOY>(
  key: string,
  dependencies: _.List<$ref.Ref$>,
  view: () => Element$<UOY>
): Element$<UOY>;

export function to_keyed<UPD>(key: string, node: Element$<UPD>): Element$<UPD>;

export function to_json<UPG>(
  node: Element$<UPG>,
  memos: $mutable_map.MutableMap$<() => Element$<UPG>, Element$<UPG>>
): $json.Json$;

export function to_string_tree(node: Element$<any>, parent_namespace: string): $string_tree.StringTree$;

export function to_string(node: Element$<any>): string;

export function to_snapshot(node: Element$<any>, debug: boolean): string;
