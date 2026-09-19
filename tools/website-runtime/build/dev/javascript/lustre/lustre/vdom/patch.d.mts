import type * as $json from "../../../gleam_json/gleam/json.d.mts";
import type * as _ from "../../gleam.d.mts";
import type * as $mutable_map from "../../lustre/internals/mutable_map.d.mts";
import type * as $vattr from "../../lustre/vdom/vattr.d.mts";
import type * as $vnode from "../../lustre/vdom/vnode.d.mts";

export class Patch<WHO> extends _.CustomType {
  /** @deprecated */
  constructor(
    index: number,
    path: _.List<number>,
    removed: number,
    changes: _.List<Change$<WHO>>,
    children: _.List<Patch$<WHO>>
  );
  /** @deprecated */
  index: number;
  /** @deprecated */
  path: _.List<number>;
  /** @deprecated */
  removed: number;
  /** @deprecated */
  changes: _.List<Change$<WHO>>;
  /** @deprecated */
  children: _.List<Patch$<WHO>>;
}
export function Patch$Patch<WHO>(
  index: number,
  path: _.List<number>,
  removed: number,
  changes: _.List<Change$<WHO>>,
  children: _.List<Patch$<WHO>>,
): Patch$<WHO>;
export function Patch$isPatch<WHO>(value: any): value is Patch$<unknown>;
export function Patch$Patch$0<WHO>(value: Patch$<WHO>): number;
export function Patch$Patch$index<WHO>(value: Patch$<WHO>): number;
export function Patch$Patch$1<WHO>(value: Patch$<WHO>): _.List<number>;
export function Patch$Patch$path<WHO>(value: Patch$<WHO>): _.List<number>;
export function Patch$Patch$2<WHO>(value: Patch$<WHO>): number;
export function Patch$Patch$removed<WHO>(value: Patch$<WHO>): number;
export function Patch$Patch$3<WHO>(value: Patch$<WHO>): _.List<Change$<WHO>>;
export function Patch$Patch$changes<WHO>(value: Patch$<WHO>): _.List<
  Change$<WHO>
>;
export function Patch$Patch$4<WHO>(value: Patch$<WHO>): _.List<Patch$<WHO>>;
export function Patch$Patch$children<WHO>(value: Patch$<WHO>): _.List<
  Patch$<WHO>
>;

export type Patch$<WHO> = Patch<WHO>;

export class ReplaceText extends _.CustomType {
  /** @deprecated */
  constructor(kind: number, content: string);
  /** @deprecated */
  kind: number;
  /** @deprecated */
  content: string;
}
export function Change$ReplaceText<WHP>(
  kind: number,
  content: string,
): Change$<WHP>;
export function Change$isReplaceText<WHP>(
  value: any,
): value is Change$<unknown>;
export function Change$ReplaceText$0<WHP>(value: Change$<WHP>): number;
export function Change$ReplaceText$kind<WHP>(value: Change$<WHP>): number;
export function Change$ReplaceText$1<WHP>(value: Change$<WHP>): string;
export function Change$ReplaceText$content<WHP>(value: Change$<WHP>): string;

export class ReplaceInnerHtml extends _.CustomType {
  /** @deprecated */
  constructor(kind: number, inner_html: string);
  /** @deprecated */
  kind: number;
  /** @deprecated */
  inner_html: string;
}
export function Change$ReplaceInnerHtml<WHP>(
  kind: number,
  inner_html: string,
): Change$<WHP>;
export function Change$isReplaceInnerHtml<WHP>(
  value: any,
): value is Change$<unknown>;
export function Change$ReplaceInnerHtml$0<WHP>(value: Change$<WHP>): number;
export function Change$ReplaceInnerHtml$kind<WHP>(value: Change$<WHP>): number;
export function Change$ReplaceInnerHtml$1<WHP>(value: Change$<WHP>): string;
export function Change$ReplaceInnerHtml$inner_html<WHP>(value: Change$<WHP>): string;

export class Update<WHP> extends _.CustomType {
  /** @deprecated */
  constructor(
    kind: number,
    added: _.List<$vattr.Attribute$<WHP>>,
    removed: _.List<$vattr.Attribute$<WHP>>
  );
  /** @deprecated */
  kind: number;
  /** @deprecated */
  added: _.List<$vattr.Attribute$<WHP>>;
  /** @deprecated */
  removed: _.List<$vattr.Attribute$<WHP>>;
}
export function Change$Update<WHP>(
  kind: number,
  added: _.List<$vattr.Attribute$<WHP>>,
  removed: _.List<$vattr.Attribute$<WHP>>,
): Change$<WHP>;
export function Change$isUpdate<WHP>(value: any): value is Change$<unknown>;
export function Change$Update$0<WHP>(value: Change$<WHP>): number;
export function Change$Update$kind<WHP>(value: Change$<WHP>): number;
export function Change$Update$1<WHP>(value: Change$<WHP>): _.List<
  $vattr.Attribute$<WHP>
>;
export function Change$Update$added<WHP>(value: Change$<WHP>): _.List<
  $vattr.Attribute$<WHP>
>;
export function Change$Update$2<WHP>(value: Change$<WHP>): _.List<
  $vattr.Attribute$<WHP>
>;
export function Change$Update$removed<WHP>(value: Change$<WHP>): _.List<
  $vattr.Attribute$<WHP>
>;

export class Move extends _.CustomType {
  /** @deprecated */
  constructor(kind: number, key: string, before: number);
  /** @deprecated */
  kind: number;
  /** @deprecated */
  key: string;
  /** @deprecated */
  before: number;
}
export function Change$Move<WHP>(
  kind: number,
  key: string,
  before: number,
): Change$<WHP>;
export function Change$isMove<WHP>(value: any): value is Change$<unknown>;
export function Change$Move$0<WHP>(value: Change$<WHP>): number;
export function Change$Move$kind<WHP>(value: Change$<WHP>): number;
export function Change$Move$1<WHP>(value: Change$<WHP>): string;
export function Change$Move$key<WHP>(value: Change$<WHP>): string;
export function Change$Move$2<WHP>(value: Change$<WHP>): number;
export function Change$Move$before<WHP>(value: Change$<WHP>): number;

export class Replace<WHP> extends _.CustomType {
  /** @deprecated */
  constructor(kind: number, index: number, with$: $vnode.Element$<WHP>);
  /** @deprecated */
  kind: number;
  /** @deprecated */
  index: number;
  /** @deprecated */
  with: $vnode.Element$<WHP>;
}
export function Change$Replace<WHP>(
  kind: number,
  index: number,
  with$: $vnode.Element$<WHP>,
): Change$<WHP>;
export function Change$isReplace<WHP>(value: any): value is Change$<unknown>;
export function Change$Replace$0<WHP>(value: Change$<WHP>): number;
export function Change$Replace$kind<WHP>(value: Change$<WHP>): number;
export function Change$Replace$1<WHP>(value: Change$<WHP>): number;
export function Change$Replace$index<WHP>(value: Change$<WHP>): number;
export function Change$Replace$2<WHP>(value: Change$<WHP>): $vnode.Element$<WHP>;
export function Change$Replace$with<WHP>(
  value: Change$<WHP>,
): $vnode.Element$<WHP>;

export class Remove extends _.CustomType {
  /** @deprecated */
  constructor(kind: number, index: number);
  /** @deprecated */
  kind: number;
  /** @deprecated */
  index: number;
}
export function Change$Remove<WHP>(kind: number, index: number): Change$<WHP>;
export function Change$isRemove<WHP>(value: any): value is Change$<unknown>;
export function Change$Remove$0<WHP>(value: Change$<WHP>): number;
export function Change$Remove$kind<WHP>(value: Change$<WHP>): number;
export function Change$Remove$1<WHP>(value: Change$<WHP>): number;
export function Change$Remove$index<WHP>(value: Change$<WHP>): number;

export class Insert<WHP> extends _.CustomType {
  /** @deprecated */
  constructor(
    kind: number,
    children: _.List<$vnode.Element$<WHP>>,
    before: number
  );
  /** @deprecated */
  kind: number;
  /** @deprecated */
  children: _.List<$vnode.Element$<WHP>>;
  /** @deprecated */
  before: number;
}
export function Change$Insert<WHP>(
  kind: number,
  children: _.List<$vnode.Element$<WHP>>,
  before: number,
): Change$<WHP>;
export function Change$isInsert<WHP>(value: any): value is Change$<unknown>;
export function Change$Insert$0<WHP>(value: Change$<WHP>): number;
export function Change$Insert$kind<WHP>(value: Change$<WHP>): number;
export function Change$Insert$1<WHP>(value: Change$<WHP>): _.List<
  $vnode.Element$<WHP>
>;
export function Change$Insert$children<WHP>(value: Change$<WHP>): _.List<
  $vnode.Element$<WHP>
>;
export function Change$Insert$2<WHP>(value: Change$<WHP>): number;
export function Change$Insert$before<WHP>(value: Change$<WHP>): number;

export type Change$<WHP> = ReplaceText | ReplaceInnerHtml | Update<WHP> | Move | Replace<
  WHP
> | Remove | Insert<WHP>;

export function Change$kind<WHP>(value: Change$<WHP>): number;

export const replace_text_kind: number;

export const replace_inner_html_kind: number;

export const update_kind: number;

export const move_kind: number;

export const remove_kind: number;

export const replace_kind: number;

export const insert_kind: number;

export function new$<WHQ>(
  index: number,
  removed: number,
  changes: _.List<Change$<WHQ>>,
  children: _.List<Patch$<WHQ>>
): Patch$<WHQ>;

export function replace_text(content: string): Change$<any>;

export function replace_inner_html(inner_html: string): Change$<any>;

export function update<WIA>(
  added: _.List<$vattr.Attribute$<WIA>>,
  removed: _.List<$vattr.Attribute$<WIA>>
): Change$<WIA>;

export function move(key: string, before: number): Change$<any>;

export function remove(index: number): Change$<any>;

export function replace<WIK>(index: number, with$: $vnode.Element$<WIK>): Change$<
  WIK
>;

export function insert<WIN>(
  children: _.List<$vnode.Element$<WIN>>,
  before: number
): Change$<WIN>;

export function is_empty(patch: Patch$<any>): boolean;

export function add_parent<WIT>(child: Patch$<WIT>, index: number): Patch$<WIT>;

export function to_json<WIW>(
  patch: Patch$<WIW>,
  memos: $mutable_map.MutableMap$<
    () => $vnode.Element$<WIW>,
    $vnode.Element$<WIW>
  >
): $json.Json$;
