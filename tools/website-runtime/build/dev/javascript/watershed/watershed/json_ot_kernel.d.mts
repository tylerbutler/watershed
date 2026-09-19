import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $json_ot from "../watershed/json_ot.d.mts";
import type * as $ot_client from "../watershed/ot_client.d.mts";

export class JsonOtState extends _.CustomType {
  /** @deprecated */
  constructor(
    sequenced: $json_ot.JsonValue$,
    log: _.List<$ot_client.LogEntry$<_.List<$json_ot.Component$>>>,
    pending: $ot_client.Pending$<_.List<$json_ot.Component$>>,
    outbound: $option.Option$<JsonOtWireOperation$>
  );
  /** @deprecated */
  sequenced: $json_ot.JsonValue$;
  /** @deprecated */
  log: _.List<$ot_client.LogEntry$<_.List<$json_ot.Component$>>>;
  /** @deprecated */
  pending: $ot_client.Pending$<_.List<$json_ot.Component$>>;
  /** @deprecated */
  outbound: $option.Option$<JsonOtWireOperation$>;
}
export function JsonOtState$JsonOtState(
  sequenced: $json_ot.JsonValue$,
  log: _.List<$ot_client.LogEntry$<_.List<$json_ot.Component$>>>,
  pending: $ot_client.Pending$<_.List<$json_ot.Component$>>,
  outbound: $option.Option$<JsonOtWireOperation$>,
): JsonOtState$;
export function JsonOtState$isJsonOtState(value: any): value is JsonOtState$;
export function JsonOtState$JsonOtState$0(value: JsonOtState$): $json_ot.JsonValue$;
export function JsonOtState$JsonOtState$sequenced(
  value: JsonOtState$,
): $json_ot.JsonValue$;
export function JsonOtState$JsonOtState$1(value: JsonOtState$): _.List<
  $ot_client.LogEntry$<_.List<$json_ot.Component$>>
>;
export function JsonOtState$JsonOtState$log(value: JsonOtState$): _.List<
  $ot_client.LogEntry$<_.List<$json_ot.Component$>>
>;
export function JsonOtState$JsonOtState$2(value: JsonOtState$): $ot_client.Pending$<
  _.List<$json_ot.Component$>
>;
export function JsonOtState$JsonOtState$pending(value: JsonOtState$): $ot_client.Pending$<
  _.List<$json_ot.Component$>
>;
export function JsonOtState$JsonOtState$3(value: JsonOtState$): $option.Option$<
  JsonOtWireOperation$
>;
export function JsonOtState$JsonOtState$outbound(value: JsonOtState$): $option.Option$<
  JsonOtWireOperation$
>;

export type JsonOtState$ = JsonOtState;

export class JsonOtWireOperation extends _.CustomType {
  /** @deprecated */
  constructor(
    reference_sequence_number: number,
    components: _.List<$json_ot.Component$>
  );
  /** @deprecated */
  reference_sequence_number: number;
  /** @deprecated */
  components: _.List<$json_ot.Component$>;
}
export function JsonOtWireOperation$JsonOtWireOperation(
  reference_sequence_number: number,
  components: _.List<$json_ot.Component$>,
): JsonOtWireOperation$;
export function JsonOtWireOperation$isJsonOtWireOperation(
  value: any,
): value is JsonOtWireOperation$;
export function JsonOtWireOperation$JsonOtWireOperation$0(value: JsonOtWireOperation$): number;
export function JsonOtWireOperation$JsonOtWireOperation$reference_sequence_number(
  value: JsonOtWireOperation$,
): number;
export function JsonOtWireOperation$JsonOtWireOperation$1(value: JsonOtWireOperation$): _.List<
  $json_ot.Component$
>;
export function JsonOtWireOperation$JsonOtWireOperation$components(value: JsonOtWireOperation$): _.List<
  $json_ot.Component$
>;

export type JsonOtWireOperation$ = JsonOtWireOperation;

export class DocumentChanged extends _.CustomType {
  /** @deprecated */
  constructor(path: _.List<$json_ot.PathKey$>, local: boolean);
  /** @deprecated */
  path: _.List<$json_ot.PathKey$>;
  /** @deprecated */
  local: boolean;
}
export function JsonOtEvent$DocumentChanged(
  path: _.List<$json_ot.PathKey$>,
  local: boolean,
): JsonOtEvent$;
export function JsonOtEvent$isDocumentChanged(
  value: any,
): value is JsonOtEvent$;
export function JsonOtEvent$DocumentChanged$0(value: JsonOtEvent$): _.List<
  $json_ot.PathKey$
>;
export function JsonOtEvent$DocumentChanged$path(value: JsonOtEvent$): _.List<
  $json_ot.PathKey$
>;
export function JsonOtEvent$DocumentChanged$1(value: JsonOtEvent$): boolean;
export function JsonOtEvent$DocumentChanged$local(value: JsonOtEvent$): boolean;

export type JsonOtEvent$ = DocumentChanged;

export class UnexpectedAck extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedAck(detail: string): KernelError$;
export function KernelError$isUnexpectedAck(value: any): value is KernelError$;
export function KernelError$UnexpectedAck$0(value: KernelError$): string;
export function KernelError$UnexpectedAck$detail(value: KernelError$): string;

export class OtFailure extends _.CustomType {
  /** @deprecated */
  constructor(error: $json_ot.OtError$);
  /** @deprecated */
  error: $json_ot.OtError$;
}
export function KernelError$OtFailure(error: $json_ot.OtError$): KernelError$;
export function KernelError$isOtFailure(value: any): value is KernelError$;
export function KernelError$OtFailure$0(value: KernelError$): $json_ot.OtError$;
export function KernelError$OtFailure$error(value: KernelError$): $json_ot.OtError$;

export type KernelError$ = UnexpectedAck | OtFailure;

export function from_value(document: $json_ot.JsonValue$): JsonOtState$;

export function new$(): JsonOtState$;

export function from_summary(document: $json_ot.JsonValue$): JsonOtState$;

export function summary(state: JsonOtState$): $json_ot.JsonValue$;

export function apply_operation(
  document: $json_ot.JsonValue$,
  operation: _.List<$json_ot.Component$>
): _.Result<$json_ot.JsonValue$, KernelError$>;

export function view(state: JsonOtState$): _.Result<
  $json_ot.JsonValue$,
  KernelError$
>;

export function transform(
  a: _.List<$json_ot.Component$>,
  b: _.List<$json_ot.Component$>,
  side: $json_ot.Side$
): _.Result<_.List<$json_ot.Component$>, KernelError$>;

export function compose(
  a: _.List<$json_ot.Component$>,
  b: _.List<$json_ot.Component$>
): _.List<$json_ot.Component$>;

export function invert(operation: _.List<$json_ot.Component$>): _.List<
  $json_ot.Component$
>;

export function submit(
  state: JsonOtState$,
  components: _.List<$json_ot.Component$>,
  reference_sequence_number: number
): _.Result<
  [JsonOtState$, $option.Option$<JsonOtWireOperation$>, _.List<JsonOtEvent$>],
  KernelError$
>;

export function apply_remote(
  state: JsonOtState$,
  wire: JsonOtWireOperation$,
  sequence_number: number,
  minimum_sequence_number: number
): _.Result<[JsonOtState$, _.List<JsonOtEvent$>], KernelError$>;

export function ack_local(
  state: JsonOtState$,
  x1: JsonOtWireOperation$,
  sequence_number: number,
  minimum_sequence_number: number
): _.Result<[JsonOtState$, _.List<JsonOtEvent$>], KernelError$>;

export function take_outbound(state: JsonOtState$): [
  JsonOtState$,
  $option.Option$<JsonOtWireOperation$>
];
