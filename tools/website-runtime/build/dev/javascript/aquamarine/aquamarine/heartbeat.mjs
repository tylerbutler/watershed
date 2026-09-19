/// <reference types="./heartbeat.d.mts" />
import * as $process from "../../gleam_erlang/gleam/erlang/process.mjs";
import * as $actor from "../../gleam_otp/gleam/otp/actor.mjs";
import * as $codec from "../aquamarine/codec.mjs";
import * as $ref from "../aquamarine/ref.mjs";
import { CustomType as $CustomType } from "../gleam.mjs";

class Heartbeat extends $CustomType {
  constructor(subject) {
    super();
    this.subject = subject;
  }
}

class Tick extends $CustomType {}
const Message$Tick$const = new Tick();

class Stop extends $CustomType {}
const Message$Stop$const = new Stop();

class State extends $CustomType {
  constructor(self, send_fn, interval_ms, counter, codec) {
    super();
    this.self = self;
    this.send_fn = send_fn;
    this.interval_ms = interval_ms;
    this.counter = counter;
    this.codec = codec;
  }
}
