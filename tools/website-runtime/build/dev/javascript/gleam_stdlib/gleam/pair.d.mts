export function first<CMB>(pair: [CMB, any]): CMB;

export function second<CME>(pair: [any, CME]): CME;

export function swap<CMF, CMG>(pair: [CMF, CMG]): [CMG, CMF];

export function map_first<CMH, CMI, CMJ>(
  pair: [CMH, CMI],
  fun: (x0: CMH) => CMJ
): [CMJ, CMI];

export function map_second<CMK, CML, CMM>(
  pair: [CMK, CML],
  fun: (x0: CML) => CMM
): [CMK, CMM];

export function new$<CMN, CMO>(first: CMN, second: CMO): [CMN, CMO];
