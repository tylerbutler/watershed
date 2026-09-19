import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";

declare class Field<BFIQ> extends _.CustomType {
  /** @deprecated */
  constructor(
    key: string,
    encode: (x0: BFIQ) => $json.Json$,
    decode: $decode.Decoder$<BFIQ>
  );
  /** @deprecated */
  key: string;
  /** @deprecated */
  encode: (x0: BFIQ) => $json.Json$;
  /** @deprecated */
  decode: $decode.Decoder$<BFIQ>;
}

export type Field$<BFIP, BFIQ> = Field<BFIQ>;

declare class ChildField extends _.CustomType {
  /** @deprecated */
  constructor(key: string);
  /** @deprecated */
  key: string;
}

export type ChildField$<BFIR, BFIS> = ChildField;

export class Missing extends _.CustomType {
  /** @deprecated */
  constructor(key: string);
  /** @deprecated */
  key: string;
}
export function FieldError$Missing(key: string): FieldError$;
export function FieldError$isMissing(value: any): value is FieldError$;
export function FieldError$Missing$0(value: FieldError$): string;
export function FieldError$Missing$key(value: FieldError$): string;

export class Invalid extends _.CustomType {
  /** @deprecated */
  constructor(reason: $json.DecodeError$);
  /** @deprecated */
  reason: $json.DecodeError$;
}
export function FieldError$Invalid(reason: $json.DecodeError$): FieldError$;
export function FieldError$isInvalid(value: any): value is FieldError$;
export function FieldError$Invalid$0(value: FieldError$): $json.DecodeError$;
export function FieldError$Invalid$reason(value: FieldError$): $json.DecodeError$;

export class UnknownKeys extends _.CustomType {
  /** @deprecated */
  constructor(keys: _.List<string>);
  /** @deprecated */
  keys: _.List<string>;
}
export function FieldError$UnknownKeys(keys: _.List<string>): FieldError$;
export function FieldError$isUnknownKeys(value: any): value is FieldError$;
export function FieldError$UnknownKeys$0(value: FieldError$): _.List<string>;
export function FieldError$UnknownKeys$keys(value: FieldError$): _.List<string>;

export class SchemaMismatch extends _.CustomType {
  /** @deprecated */
  constructor(expected: number, found: number);
  /** @deprecated */
  expected: number;
  /** @deprecated */
  found: number;
}
export function FieldError$SchemaMismatch(
  expected: number,
  found: number,
): FieldError$;
export function FieldError$isSchemaMismatch(value: any): value is FieldError$;
export function FieldError$SchemaMismatch$0(value: FieldError$): number;
export function FieldError$SchemaMismatch$expected(value: FieldError$): number;
export function FieldError$SchemaMismatch$1(value: FieldError$): number;
export function FieldError$SchemaMismatch$found(value: FieldError$): number;

export type FieldError$ = Missing | Invalid | UnknownKeys | SchemaMismatch;

export type MapChannel$ = any;

export type CounterChannel$ = any;

export type LwwRegisterChannel$ = any;

export type LwwMapChannel$ = any;

export type MvRegisterChannel$ = any;

export type OrMapChannel$ = any;

export type OrSetChannel$ = any;

export type ClaimsChannel$ = any;

export type RegisterCollectionChannel$ = any;

export type TaskManagerChannel$ = any;

export type JsonOtChannel$ = any;

export type RichTextChannel$ = any;

export type GSetChannel$ = any;

export type TwoPSetChannel$ = any;

export type DirectoryChannel$ = any;

export type PnCounterChannel$ = any;

export type GCounterChannel$ = any;

export type PactMapChannel$ = any;

export type OrderedCollectionChannel$ = any;

export type SequenceChannel$ = any;

export type TextChannel$ = any;

declare class ChannelField extends _.CustomType {
  /** @deprecated */
  constructor(key: string);
  /** @deprecated */
  key: string;
}

export type ChannelField$<BFIT, BFIU> = ChannelField;

export class FieldChange<BFIV> extends _.CustomType {
  /** @deprecated */
  constructor(
    value: _.Result<$option.Option$<BFIV>, FieldError$>,
    previous: _.Result<$option.Option$<BFIV>, FieldError$>,
    local: boolean
  );
  /** @deprecated */
  value: _.Result<$option.Option$<BFIV>, FieldError$>;
  /** @deprecated */
  previous: _.Result<$option.Option$<BFIV>, FieldError$>;
  /** @deprecated */
  local: boolean;
}
export function FieldChange$FieldChange<BFIV>(
  value: _.Result<$option.Option$<BFIV>, FieldError$>,
  previous: _.Result<$option.Option$<BFIV>, FieldError$>,
  local: boolean,
): FieldChange$<BFIV>;
export function FieldChange$isFieldChange<BFIV>(
  value: any,
): value is FieldChange$<unknown>;
export function FieldChange$FieldChange$0<BFIV>(value: FieldChange$<BFIV>): _.Result<
  $option.Option$<BFIV>,
  FieldError$
>;
export function FieldChange$FieldChange$value<BFIV>(value: FieldChange$<BFIV>): _.Result<
  $option.Option$<BFIV>,
  FieldError$
>;
export function FieldChange$FieldChange$1<BFIV>(value: FieldChange$<BFIV>): _.Result<
  $option.Option$<BFIV>,
  FieldError$
>;
export function FieldChange$FieldChange$previous<BFIV>(value: FieldChange$<BFIV>): _.Result<
  $option.Option$<BFIV>,
  FieldError$
>;
export function FieldChange$FieldChange$2<BFIV>(value: FieldChange$<BFIV>): boolean;
export function FieldChange$FieldChange$local<BFIV>(
  value: FieldChange$<BFIV>,
): boolean;

export type FieldChange$<BFIV> = FieldChange<BFIV>;

export class Put extends _.CustomType {
  /** @deprecated */
  constructor(key: string, value: $json.Json$);
  /** @deprecated */
  key: string;
  /** @deprecated */
  value: $json.Json$;
}
export function WriteOperation$Put(
  key: string,
  value: $json.Json$,
): WriteOperation$;
export function WriteOperation$isPut(value: any): value is WriteOperation$;
export function WriteOperation$Put$0(value: WriteOperation$): string;
export function WriteOperation$Put$key(value: WriteOperation$): string;
export function WriteOperation$Put$1(value: WriteOperation$): $json.Json$;
export function WriteOperation$Put$value(value: WriteOperation$): $json.Json$;

export class Delete extends _.CustomType {
  /** @deprecated */
  constructor(key: string);
  /** @deprecated */
  key: string;
}
export function WriteOperation$Delete(key: string): WriteOperation$;
export function WriteOperation$isDelete(value: any): value is WriteOperation$;
export function WriteOperation$Delete$0(value: WriteOperation$): string;
export function WriteOperation$Delete$key(value: WriteOperation$): string;

export type WriteOperation$ = Put | Delete;

export function WriteOperation$key(value: WriteOperation$): string;

declare class Schema<BFIX> extends _.CustomType {
  /** @deprecated */
  constructor(
    decode: $decode.Decoder$<BFIX>,
    to_operations: (x0: BFIX) => _.List<WriteOperation$>,
    known_keys: $option.Option$<_.List<string>>,
    version: $option.Option$<number>,
    declared_keys: $option.Option$<_.List<string>>
  );
  /** @deprecated */
  decode: $decode.Decoder$<BFIX>;
  /** @deprecated */
  to_operations: (x0: BFIX) => _.List<WriteOperation$>;
  /** @deprecated */
  known_keys: $option.Option$<_.List<string>>;
  /** @deprecated */
  version: $option.Option$<number>;
  /** @deprecated */
  declared_keys: $option.Option$<_.List<string>>;
}

export type Schema$<BFIW, BFIX> = Schema<BFIX>;

declare class Prop<BFIZ, BFJA> extends _.CustomType {
  /** @deprecated */
  constructor(
    key: string,
    decoder: $decode.Decoder$<BFJA>,
    fallback: $option.Option$<BFJA>,
    write: (x0: BFIZ) => WriteOperation$
  );
  /** @deprecated */
  key: string;
  /** @deprecated */
  decoder: $decode.Decoder$<BFJA>;
  /** @deprecated */
  fallback: $option.Option$<BFJA>;
  /** @deprecated */
  write: (x0: BFIZ) => WriteOperation$;
}

export type Prop$<BFIY, BFIZ, BFJA> = Prop<BFIZ, BFJA>;

export const version_key: string;

export function field<BFJB>(
  key: string,
  encode: (x0: BFJB) => $json.Json$,
  decode: $decode.Decoder$<BFJB>
): Field$<any, BFJB>;

export function child_field(key: string): ChildField$<any, any>;

export function channel_field(key: string): ChannelField$<any, any>;

export function channel_field_key(field: ChannelField$<any, any>): string;

export function field_key(field: Field$<any, any>): string;

export function child_key(field: ChildField$<any, any>): string;

export function encode_value<BFKB>(field: Field$<any, BFKB>, value: BFKB): $json.Json$;

export function decode_value<BFKF>(
  field: Field$<any, BFKF>,
  stored: $json.Json$
): _.Result<BFKF, FieldError$>;

export function decode_optional<BFKL>(
  field: Field$<any, BFKL>,
  stored: $option.Option$<$json.Json$>
): _.Result<$option.Option$<BFKL>, FieldError$>;

export function schema<BFKS>(
  decode: $decode.Decoder$<BFKS>,
  to_entries: (x0: BFKS) => _.List<[string, $json.Json$]>
): Schema$<any, BFKS>;

export function sealed<BFKY, BFKZ>(
  schema: Schema$<BFKY, BFKZ>,
  keys: _.List<string>
): Schema$<BFKY, BFKZ>;

export function sealed_known<BFLF, BFLG>(schema: Schema$<BFLF, BFLG>): _.Result<
  Schema$<BFLF, BFLG>,
  undefined
>;

export function versioned<BFLN, BFLO>(
  schema: Schema$<BFLN, BFLO>,
  version: number
): Schema$<BFLN, BFLO>;

export function decode_entries<BFLU>(
  schema: Schema$<any, BFLU>,
  entries: _.List<[string, $json.Json$]>
): _.Result<BFLU, FieldError$>;

export function encode_operations<BFMB>(schema: Schema$<any, BFMB>, value: BFMB): _.List<
  WriteOperation$
>;

export function stamp_entry(schema: Schema$<any, any>): $option.Option$<
  [string, $json.Json$]
>;

export function prop<BFMR, BFMS, BFMV>(
  field: Field$<BFMR, BFMS>,
  get: (x0: BFMV) => BFMS
): Prop$<BFMR, BFMV, BFMS>;

export function optional_prop<BFMZ, BFNA, BFND>(
  field: Field$<BFMZ, BFNA>,
  get: (x0: BFND) => $option.Option$<BFNA>
): Prop$<BFMZ, BFND, $option.Option$<BFNA>>;

export function record1<BFNY, BFNZ, BFOA>(
  ctor: (x0: BFNY) => BFNZ,
  p1: Prop$<BFOA, BFNZ, BFNY>
): Schema$<BFOA, BFNZ>;

export function record2<BFOG, BFOH, BFOI, BFOJ>(
  ctor: (x0: BFOG, x1: BFOH) => BFOI,
  p1: Prop$<BFOJ, BFOI, BFOG>,
  p2: Prop$<BFOJ, BFOI, BFOH>
): Schema$<BFOJ, BFOI>;

export function record3<BFOS, BFOT, BFOU, BFOV, BFOW>(
  ctor: (x0: BFOS, x1: BFOT, x2: BFOU) => BFOV,
  p1: Prop$<BFOW, BFOV, BFOS>,
  p2: Prop$<BFOW, BFOV, BFOT>,
  p3: Prop$<BFOW, BFOV, BFOU>
): Schema$<BFOW, BFOV>;

export function record4<BFPI, BFPJ, BFPK, BFPL, BFPM, BFPN>(
  ctor: (x0: BFPI, x1: BFPJ, x2: BFPK, x3: BFPL) => BFPM,
  p1: Prop$<BFPN, BFPM, BFPI>,
  p2: Prop$<BFPN, BFPM, BFPJ>,
  p3: Prop$<BFPN, BFPM, BFPK>,
  p4: Prop$<BFPN, BFPM, BFPL>
): Schema$<BFPN, BFPM>;

export function record5<BFQC, BFQD, BFQE, BFQF, BFQG, BFQH, BFQI>(
  ctor: (x0: BFQC, x1: BFQD, x2: BFQE, x3: BFQF, x4: BFQG) => BFQH,
  p1: Prop$<BFQI, BFQH, BFQC>,
  p2: Prop$<BFQI, BFQH, BFQD>,
  p3: Prop$<BFQI, BFQH, BFQE>,
  p4: Prop$<BFQI, BFQH, BFQF>,
  p5: Prop$<BFQI, BFQH, BFQG>
): Schema$<BFQI, BFQH>;

export function record6<BFRA, BFRB, BFRC, BFRD, BFRE, BFRF, BFRG, BFRH>(
  ctor: (x0: BFRA, x1: BFRB, x2: BFRC, x3: BFRD, x4: BFRE, x5: BFRF) => BFRG,
  p1: Prop$<BFRH, BFRG, BFRA>,
  p2: Prop$<BFRH, BFRG, BFRB>,
  p3: Prop$<BFRH, BFRG, BFRC>,
  p4: Prop$<BFRH, BFRG, BFRD>,
  p5: Prop$<BFRH, BFRG, BFRE>,
  p6: Prop$<BFRH, BFRG, BFRF>
): Schema$<BFRH, BFRG>;

export function record7<BFSC, BFSD, BFSE, BFSF, BFSG, BFSH, BFSI, BFSJ, BFSK>(
  ctor: (x0: BFSC, x1: BFSD, x2: BFSE, x3: BFSF, x4: BFSG, x5: BFSH, x6: BFSI) => BFSJ,
  p1: Prop$<BFSK, BFSJ, BFSC>,
  p2: Prop$<BFSK, BFSJ, BFSD>,
  p3: Prop$<BFSK, BFSJ, BFSE>,
  p4: Prop$<BFSK, BFSJ, BFSF>,
  p5: Prop$<BFSK, BFSJ, BFSG>,
  p6: Prop$<BFSK, BFSJ, BFSH>,
  p7: Prop$<BFSK, BFSJ, BFSI>
): Schema$<BFSK, BFSJ>;

export function record8<
  BFTI,
  BFTJ,
  BFTK,
  BFTL,
  BFTM,
  BFTN,
  BFTO,
  BFTP,
  BFTQ,
  BFTR
>(
  ctor: (
    x0: BFTI,
    x1: BFTJ,
    x2: BFTK,
    x3: BFTL,
    x4: BFTM,
    x5: BFTN,
    x6: BFTO,
    x7: BFTP
  ) => BFTQ,
  p1: Prop$<BFTR, BFTQ, BFTI>,
  p2: Prop$<BFTR, BFTQ, BFTJ>,
  p3: Prop$<BFTR, BFTQ, BFTK>,
  p4: Prop$<BFTR, BFTQ, BFTL>,
  p5: Prop$<BFTR, BFTQ, BFTM>,
  p6: Prop$<BFTR, BFTQ, BFTN>,
  p7: Prop$<BFTR, BFTQ, BFTO>,
  p8: Prop$<BFTR, BFTQ, BFTP>
): Schema$<BFTR, BFTQ>;

export function record9<
  BFUS,
  BFUT,
  BFUU,
  BFUV,
  BFUW,
  BFUX,
  BFUY,
  BFUZ,
  BFVA,
  BFVB,
  BFVC
>(
  ctor: (
    x0: BFUS,
    x1: BFUT,
    x2: BFUU,
    x3: BFUV,
    x4: BFUW,
    x5: BFUX,
    x6: BFUY,
    x7: BFUZ,
    x8: BFVA
  ) => BFVB,
  p1: Prop$<BFVC, BFVB, BFUS>,
  p2: Prop$<BFVC, BFVB, BFUT>,
  p3: Prop$<BFVC, BFVB, BFUU>,
  p4: Prop$<BFVC, BFVB, BFUV>,
  p5: Prop$<BFVC, BFVB, BFUW>,
  p6: Prop$<BFVC, BFVB, BFUX>,
  p7: Prop$<BFVC, BFVB, BFUY>,
  p8: Prop$<BFVC, BFVB, BFUZ>,
  p9: Prop$<BFVC, BFVB, BFVA>
): Schema$<BFVC, BFVB>;
