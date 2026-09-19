import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";

export class SequencedOpParams extends _.CustomType {
  /** @deprecated */
  constructor(
    client_id: string,
    sequence_number: number,
    minimum_sequence_number: number,
    client_sequence_number: number,
    reference_sequence_number: number,
    op_type: string,
    contents: $dynamic.Dynamic$,
    metadata: $dynamic.Dynamic$,
    timestamp: number
  );
  /** @deprecated */
  client_id: string;
  /** @deprecated */
  sequence_number: number;
  /** @deprecated */
  minimum_sequence_number: number;
  /** @deprecated */
  client_sequence_number: number;
  /** @deprecated */
  reference_sequence_number: number;
  /** @deprecated */
  op_type: string;
  /** @deprecated */
  contents: $dynamic.Dynamic$;
  /** @deprecated */
  metadata: $dynamic.Dynamic$;
  /** @deprecated */
  timestamp: number;
}
export function SequencedOpParams$SequencedOpParams(
  client_id: string,
  sequence_number: number,
  minimum_sequence_number: number,
  client_sequence_number: number,
  reference_sequence_number: number,
  op_type: string,
  contents: $dynamic.Dynamic$,
  metadata: $dynamic.Dynamic$,
  timestamp: number,
): SequencedOpParams$;
export function SequencedOpParams$isSequencedOpParams(
  value: any,
): value is SequencedOpParams$;
export function SequencedOpParams$SequencedOpParams$0(value: SequencedOpParams$): string;
export function SequencedOpParams$SequencedOpParams$client_id(
  value: SequencedOpParams$,
): string;
export function SequencedOpParams$SequencedOpParams$1(value: SequencedOpParams$): number;
export function SequencedOpParams$SequencedOpParams$sequence_number(
  value: SequencedOpParams$,
): number;
export function SequencedOpParams$SequencedOpParams$2(value: SequencedOpParams$): number;
export function SequencedOpParams$SequencedOpParams$minimum_sequence_number(
  value: SequencedOpParams$,
): number;
export function SequencedOpParams$SequencedOpParams$3(value: SequencedOpParams$): number;
export function SequencedOpParams$SequencedOpParams$client_sequence_number(
  value: SequencedOpParams$,
): number;
export function SequencedOpParams$SequencedOpParams$4(value: SequencedOpParams$): number;
export function SequencedOpParams$SequencedOpParams$reference_sequence_number(
  value: SequencedOpParams$,
): number;
export function SequencedOpParams$SequencedOpParams$5(value: SequencedOpParams$): string;
export function SequencedOpParams$SequencedOpParams$op_type(
  value: SequencedOpParams$,
): string;
export function SequencedOpParams$SequencedOpParams$6(value: SequencedOpParams$): $dynamic.Dynamic$;
export function SequencedOpParams$SequencedOpParams$contents(
  value: SequencedOpParams$,
): $dynamic.Dynamic$;
export function SequencedOpParams$SequencedOpParams$7(value: SequencedOpParams$): $dynamic.Dynamic$;
export function SequencedOpParams$SequencedOpParams$metadata(
  value: SequencedOpParams$,
): $dynamic.Dynamic$;
export function SequencedOpParams$SequencedOpParams$8(value: SequencedOpParams$): number;
export function SequencedOpParams$SequencedOpParams$timestamp(
  value: SequencedOpParams$,
): number;

export type SequencedOpParams$ = SequencedOpParams;

export function negotiate_features(
  server_features: $dict.Dict$<string, boolean>,
  client_features: $dict.Dict$<string, boolean>
): $dict.Dict$<string, boolean>;

export function negotiate_version(
  supported_versions: _.List<string>,
  client_versions: _.List<string>
): string;

export function validate_summarize_contents(
  contents: $dict.Dict$<string, $dynamic.Dynamic$>
): _.Result<undefined, string>;

export function determine_signal_recipients(
  sender_client_id: string,
  targeted_clients: $option.Option$<_.List<string>>,
  ignored_clients: $option.Option$<_.List<string>>,
  single_target: $option.Option$<string>,
  all_client_ids: _.List<string>
): _.List<string>;

export function add_to_history<ADFF>(
  op: ADFF,
  history: _.List<ADFF>,
  max_size: number
): _.List<ADFF>;

export function build_sequenced_op(params: SequencedOpParams$): _.List<
  [string, $dynamic.Dynamic$]
>;

export function build_summary_ack(
  handle: string,
  sn: number,
  msn: number,
  timestamp: number
): _.List<[string, $dynamic.Dynamic$]>;
