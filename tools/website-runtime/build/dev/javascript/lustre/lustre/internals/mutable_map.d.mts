export type MutableMap$<UKH, UKI> = any;

export function new$(): MutableMap$<any, any>;

export function unsafe_get<UKN, UKO>(map: MutableMap$<UKN, UKO>, key: UKN): UKO;

export function get_or_compute<UKV, UKW>(
  map: MutableMap$<UKV, UKW>,
  key: UKV,
  compute: () => UKW
): UKW;

export function has_key<ULF>(map: MutableMap$<ULF, any>, key: ULF): boolean;

export function insert<ULN, ULO>(
  map: MutableMap$<ULN, ULO>,
  key: ULN,
  value: ULO
): MutableMap$<ULN, ULO>;

export function delete$<ULZ, UMA>(map: MutableMap$<ULZ, UMA>, key: ULZ): MutableMap$<
  ULZ,
  UMA
>;

export function size(map: MutableMap$<any, any>): number;

export function is_empty(map: MutableMap$<any, any>): boolean;
