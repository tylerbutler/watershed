import type * as $string_tree from "../../gleam_stdlib/gleam/string_tree.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $ref from "../lustre/internals/ref.d.mts";
import type * as $vattr from "../lustre/vdom/vattr.d.mts";
import type * as $vnode from "../lustre/vdom/vnode.d.mts";

declare class Html extends _.CustomType {}

declare class HeadOnly extends _.CustomType {}

declare class BodyOnly extends _.CustomType {}

declare class HeadAndBody extends _.CustomType {}

declare class Other extends _.CustomType {}

type DocumentType$ = Html | HeadOnly | BodyOnly | HeadAndBody | Other;

export type Element = $vnode.Element$<any>;

export type Ref = $ref.Ref$;

export function element<UXU>(
  tag: string,
  attributes: _.List<$vattr.Attribute$<UXU>>,
  children: _.List<$vnode.Element$<UXU>>
): $vnode.Element$<UXU>;

export function namespaced<UYA>(
  namespace: string,
  tag: string,
  attributes: _.List<$vattr.Attribute$<UYA>>,
  children: _.List<$vnode.Element$<UYA>>
): $vnode.Element$<UYA>;

export function advanced<UYG>(
  namespace: string,
  tag: string,
  attributes: _.List<$vattr.Attribute$<UYG>>,
  children: _.List<$vnode.Element$<UYG>>,
  self_closing: boolean,
  void$: boolean
): $vnode.Element$<UYG>;

export function text(content: string): $vnode.Element$<any>;

export function none(): $vnode.Element$<any>;

export function fragment<UYQ>(children: _.List<$vnode.Element$<UYQ>>): $vnode.Element$<
  UYQ
>;

export function unsafe_raw_html<UYU>(
  namespace: string,
  tag: string,
  attributes: _.List<$vattr.Attribute$<UYU>>,
  inner_html: string
): $vnode.Element$<UYU>;

export function memo<UYZ>(
  dependencies: _.List<$ref.Ref$>,
  view: () => $vnode.Element$<UYZ>
): $vnode.Element$<UYZ>;

export function ref(value: any): $ref.Ref$;

export function map<UZD, UZF>(
  element: $vnode.Element$<UZD>,
  f: (x0: UZD) => UZF
): $vnode.Element$<UZF>;

export function to_string(element: $vnode.Element$<any>): string;

export function to_document_string(el: $vnode.Element$<any>): string;

export function to_string_tree(element: $vnode.Element$<any>): $string_tree.StringTree$;

export function to_document_string_tree(el: $vnode.Element$<any>): $string_tree.StringTree$;

export function to_readable_string(el: $vnode.Element$<any>): string;
