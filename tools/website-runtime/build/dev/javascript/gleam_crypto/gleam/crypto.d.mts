import type * as _ from "../gleam.d.mts";

export class Sha224 extends _.CustomType {}
export function HashAlgorithm$Sha224(): HashAlgorithm$;
export function HashAlgorithm$isSha224(value: any): value is HashAlgorithm$;

export class Sha256 extends _.CustomType {}
export function HashAlgorithm$Sha256(): HashAlgorithm$;
export function HashAlgorithm$isSha256(value: any): value is HashAlgorithm$;

export class Sha384 extends _.CustomType {}
export function HashAlgorithm$Sha384(): HashAlgorithm$;
export function HashAlgorithm$isSha384(value: any): value is HashAlgorithm$;

export class Sha512 extends _.CustomType {}
export function HashAlgorithm$Sha512(): HashAlgorithm$;
export function HashAlgorithm$isSha512(value: any): value is HashAlgorithm$;

export class Md5 extends _.CustomType {}
export function HashAlgorithm$Md5(): HashAlgorithm$;
export function HashAlgorithm$isMd5(value: any): value is HashAlgorithm$;

export class Sha1 extends _.CustomType {}
export function HashAlgorithm$Sha1(): HashAlgorithm$;
export function HashAlgorithm$isSha1(value: any): value is HashAlgorithm$;

export type HashAlgorithm$ = Sha224 | Sha256 | Sha384 | Sha512 | Md5 | Sha1;

export type Hasher$ = any;

export function strong_random_bytes(a: number): _.BitArray;

export function digest(hasher: Hasher$): _.BitArray;

export function hash_chunk(hasher: Hasher$, chunk: _.BitArray): Hasher$;

export function new_hasher(algorithm: HashAlgorithm$): Hasher$;

export function hash(algorithm: HashAlgorithm$, data: _.BitArray): _.BitArray;

export function hmac(
  data: _.BitArray,
  algorithm: HashAlgorithm$,
  key: _.BitArray
): _.BitArray;

export function secure_compare(left: _.BitArray, right: _.BitArray): boolean;

export function sign_message(
  message: _.BitArray,
  secret: _.BitArray,
  digest_type: HashAlgorithm$
): string;

export function verify_signed_message(message: string, secret: _.BitArray): _.Result<
  _.BitArray,
  undefined
>;
