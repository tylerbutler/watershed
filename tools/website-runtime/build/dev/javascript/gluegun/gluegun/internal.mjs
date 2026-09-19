/// <reference types="./internal.d.mts" />
import * as $dynamic from "../../gleam_stdlib/gleam/dynamic.mjs";
import { CustomType as $CustomType } from "../gleam.mjs";

class Connection extends $CustomType {
  constructor(raw) {
    super();
    this.raw = raw;
  }
}

class Stream extends $CustomType {
  constructor(raw) {
    super();
    this.raw = raw;
  }
}

export function connection(raw) {
  return new Connection(raw);
}

export function connection_raw(connection) {
  return connection.raw;
}

export function stream(raw) {
  return new Stream(raw);
}

export function stream_raw(stream) {
  return stream.raw;
}
