import type * as _ from "../../gleam.d.mts";
import type * as $mutable_map from "../../lustre/internals/mutable_map.d.mts";
import type * as $vattr from "../../lustre/vdom/vattr.d.mts";
import type * as $vnode from "../../lustre/vdom/vnode.d.mts";

export function element<AAMB>(
  tag: string,
  attributes: _.List<$vattr.Attribute$<AAMB>>,
  children: _.List<[string, $vnode.Element$<AAMB>]>
): $vnode.Element$<AAMB>;

export function namespaced<AAMH>(
  namespace: string,
  tag: string,
  attributes: _.List<$vattr.Attribute$<AAMH>>,
  children: _.List<[string, $vnode.Element$<AAMH>]>
): $vnode.Element$<AAMH>;

export function fragment<AAMN>(
  children: _.List<[string, $vnode.Element$<AAMN>]>
): $vnode.Element$<AAMN>;

export function ul<AAMR>(
  attributes: _.List<$vattr.Attribute$<AAMR>>,
  children: _.List<[string, $vnode.Element$<AAMR>]>
): $vnode.Element$<AAMR>;

export function ol<AAMX>(
  attributes: _.List<$vattr.Attribute$<AAMX>>,
  children: _.List<[string, $vnode.Element$<AAMX>]>
): $vnode.Element$<AAMX>;

export function div<AAND>(
  attributes: _.List<$vattr.Attribute$<AAND>>,
  children: _.List<[string, $vnode.Element$<AAND>]>
): $vnode.Element$<AAND>;

export function tbody<AANJ>(
  attributes: _.List<$vattr.Attribute$<AANJ>>,
  children: _.List<[string, $vnode.Element$<AANJ>]>
): $vnode.Element$<AANJ>;

export function dl<AANP>(
  attributes: _.List<$vattr.Attribute$<AANP>>,
  children: _.List<[string, $vnode.Element$<AANP>]>
): $vnode.Element$<AANP>;
